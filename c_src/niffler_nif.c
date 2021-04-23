/* Copyright, 2021 Dominic Letz */

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "erl_nif.h"
#include "tinycc/libtcc.h"
#include "tcclib.h"

static ERL_NIF_TERM error_result(ErlNifEnv *env, const char *error_msg);
static ERL_NIF_TERM ok_result(ErlNifEnv *env, ERL_NIF_TERM ret);
static void free_state(ErlNifEnv *env, void *obj);

static ErlNifResourceType *PROGRAM_TYPE;

typedef struct
{
	uint64_t size;
	unsigned char *data;
} Binary;

typedef struct
{
	char name[64];
	int type;
} ParamDef;

typedef union
{
	Binary binary;
	int64_t integer64;
	uint64_t uinteger64;
	double doubleval;
} Param;

typedef struct _Item
{
	struct _Item *prev;
	struct _Item *next;
	char begin;
} AllocItem;

typedef struct
{
	uint64_t method;
	AllocItem *head;
} Env;

void *niffler_alloc(Env *env, size_t size)
{
	AllocItem *item = malloc(size + sizeof(AllocItem));
	if (!item)
		return 0;

	memset(item, 0, size + sizeof(AllocItem));
	item->next = env->head;
	env->head = item;
	return &item->begin;
}

void free_env(Env *env)
{
	while (env->head)
	{
		AllocItem *head = env->head;
		if (head)
		{
			env->head = head->next;
			free(head);
		}
	}
}

#define TYPE_INT64 1
#define TYPE_UINT64 2
// #define TYPE_STRING 4
#define TYPE_BINARY 5
#define TYPE_DOUBLE 6

#define MAX_ARGS 10

static int
atom_to_type(char *atom)
{
	if (strcmp(atom, "int") == 0)
		return TYPE_INT64;
	if (strcmp(atom, "int64") == 0)
		return TYPE_INT64;
	if (strcmp(atom, "uint64") == 0)
		return TYPE_UINT64;
	// if (strcmp(atom, "char*") == 0)  return TYPE_STRING;
	if (strcmp(atom, "binary") == 0)
		return TYPE_BINARY;
	if (strcmp(atom, "double") == 0)
		return TYPE_DOUBLE;
	return -1;
}

typedef struct
{
	int size;
	ParamDef *params;
} Params;

typedef struct
{
	TCCState *state;
	Params inputs;
	Params outputs;
} Method;

static void free_methods(Method *methods, unsigned size)
{
	if (!methods)
		return;
	for (unsigned i = 0; i < size; i++)
	{
		if (methods[i].inputs.params)
			free(methods[i].inputs.params);
		if (methods[i].outputs.params)
			free(methods[i].outputs.params);
	}
}

typedef struct
{
	TCCState *state;
	const char *(*runop)(Env *, Param *, Param *);
	Method *methods;
	unsigned method_count;
} Program;

static int
load(ErlNifEnv *env, void **priv, ERL_NIF_TERM load_info)
{
	int flags = ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER;
	PROGRAM_TYPE = enif_open_resource_type(env, "Elixir.Niffler", "state", free_state, flags, NULL);
	if (PROGRAM_TYPE == 0)
		return -1;
	return 0;
}

static int
upgrade(ErlNifEnv *env, void **priv, void **old_priv, ERL_NIF_TERM load_info)
{
	return 0;
}

static void
unload(ErlNifEnv *env, void *priv)
{
	return;
}

static int
scan_param(ErlNifEnv *env, ERL_NIF_TERM erlp, ParamDef *p, unsigned size, ERL_NIF_TERM *ret)
{
	if (!size)
		return 1;

	ERL_NIF_TERM head, tail;
	if (!enif_get_list_cell(env, erlp, &head, &tail))
	{
		*ret = error_result(env, "Couldn't read nth parameter list item");
		return 0;
	}

	int arity = 0;
	const ERL_NIF_TERM *array = 0;
	if (!enif_get_tuple(env, head, &arity, &array))
	{
		*ret = error_result(env, "Parameter list element is not a tuple");
		return 0;
	}

	if (arity != 2)
	{
		*ret = error_result(env, "Parameter list element is not a 2 element tuple");
		return 0;
	}

	if (!enif_get_atom(env, array[0], p->name, sizeof(p->name), ERL_NIF_LATIN1))
	{
		ErlNifBinary bin;
		if (!enif_inspect_binary(env, array[0], &bin))
		{
			*ret = error_result(env, "Parameter element {name, type} - name is neither a string nor an atom");
			return 0;
		}

		if (bin.size > sizeof(p->name) - 1)
		{
			*ret = error_result(env, "Parameter element {name, type} - name is too long (max 63 chars)");
			return 0;
		}

		memcpy(p->name, bin.data, bin.size);
		p->name[bin.size] = 0;
	}

	char atom[32];
	if (!enif_get_atom(env, array[1], atom, sizeof(atom) - 1, ERL_NIF_LATIN1))
	{
		*ret = error_result(env, "Parameter element {name, type} - type is not an atom");
		return 0;
	}

	p->type = atom_to_type(atom);
	if (p->type < 0)
	{
		*ret = error_result(env, "Parameter element {name, type} - type is not a known type");
		return 0;
	}

	return scan_param(env, tail, p + 1, size - 1, ret);
}

static Params
scan_params(ErlNifEnv *env, ERL_NIF_TERM erl_params, ERL_NIF_TERM *ret)
{
	Params params = {};
	unsigned size;
	if (!enif_get_list_length(env, erl_params, &size))
	{
		*ret = error_result(env, "parameter is not a list");
		params.size = -1;
		return params;
	}
	params.size = size;

	if (params.size == 0)
		return params;

	if (params.size > MAX_ARGS)
	{
		*ret = error_result(env, "parameter list above maximum size");
		return params;
	}

	params.params = malloc(sizeof(params.params[0]) * params.size);

	if (!params.params)
	{
		*ret = error_result(env, "could not allocate parameter list");
		return params;
	}

	memset(params.params, 0, sizeof(params.params[0]) * params.size);

	if (!scan_param(env, erl_params, params.params, params.size, ret))
	{
		free(params.params);
		params.size = -1;
		return params;
	}

	return params;
}

static ERL_NIF_TERM
compile(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
	ErlNifBinary sourcecode;
	TCCState *state;

	if (!enif_inspect_binary(env, argv[0], &sourcecode))
		return enif_make_badarg(env);

	unsigned size;
	ERL_NIF_TERM method_list = argv[1];
	if (!enif_get_list_length(env, method_list, &size))
		return error_result(env, "parameter is not a list");

	if (size == 0)
		return error_result(env, "parameter list is empty");

	Method *methods = malloc(sizeof(Method) * size);
	if (!methods)
		return error_result(env, "could not allocate method list");

	memset(methods, 0, sizeof(Method) * size);

	for (unsigned i = 0; i < size; i++)
	{
		ERL_NIF_TERM head;
		if (!enif_get_list_cell(env, method_list, &head, &method_list)) 
			return error_result(env, "could get method list element");

		int arity;
		const ERL_NIF_TERM* tuple;
		if (!enif_get_tuple(env, head, &arity, &tuple) || arity != 2) 
			return error_result(env, "method list element is not a 2-element tuple");


		ERL_NIF_TERM ret = error_result(env, "failed to scan input parameters");
		methods[i].inputs = scan_params(env, tuple[0], &ret);
		if (methods[i].inputs.size < 0)
		{
			free_methods(methods, size);
			return ret;
		}
		ret = error_result(env, "failed to scan output parameters");
		methods[i].outputs = scan_params(env, tuple[1], &ret);
		if (methods[i].outputs.size < 0)
		{
			free_methods(methods, size);
			return ret;
		}
	}

	state = tcc_new();
	if (!state)
	{
		free_methods(methods, size);
		return error_result(env, "could not initiate tcc state");
	}

	Program *program = enif_alloc_resource(PROGRAM_TYPE, sizeof(Program));
	program->state = state;
	program->methods = methods;
	program->method_count = size;

	ERL_NIF_TERM term = enif_make_resource(env, program);
	enif_release_resource(program);

	if (tcc_set_output_type(state, TCC_OUTPUT_MEMORY) != 0)
		return error_result(env, "could not set tcc output type");

	if (tcc_compile_string(state, (const char *)sourcecode.data) != 0)
		return error_result(env, "compilation error");

	#define X(name) tcc_add_symbol(state, #name, name);
	#include "symbols.def"
	#undef X

	tcc_set_options(state, "-nostdlib");
	if (tcc_relocate(state, TCC_RELOCATE_AUTO) != 0)
		return error_result(env, "could not relocate program");

	program->runop = tcc_get_symbol(program->state, "run");
	if (!program->runop)
		return error_result(env, " run is undefined");

	return ok_result(env, term);
}

static void free_state(ErlNifEnv *env, void *obj)
{
	Program *program = (Program *)obj;
	tcc_delete(program->state);
	free_methods(program->methods, program->method_count);
}

static ERL_NIF_TERM
run(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
	Program *program;

	if (!enif_get_resource(env, argv[0], PROGRAM_TYPE, (void *)&program))
		return enif_make_badarg(env);

	uint64_t method_index;
	if (!enif_get_uint64(env, argv[1], &method_index))
		return error_result(env, "method index must be an int");

	if (method_index >= program->method_count)
		return error_result(env, "method index out of bounds");

	Method *method = &program->methods[method_index];

	Param *input = alloca(sizeof(Param) * method->inputs.size);
	Param *output = alloca(sizeof(Param) * method->outputs.size);
	memset(output, 0, sizeof(Param) * method->outputs.size);
	// Param input[MAX_ARGS] = {};
	// Param output[MAX_ARGS] = {};

	ERL_NIF_TERM head, tail = argv[2];
	for (int i = 0; i < method->inputs.size; i++)
	{
		if (!enif_get_list_cell(env, tail, &head, &tail))
			return error_result(env, "not enough arguments");

		switch (method->inputs.params[i].type)
		{
		case TYPE_INT64:
			if (!enif_get_int64(env, head, &input[i].integer64))
				return error_result(env, "parameter should be int64");
			break;
		case TYPE_UINT64:
			if (!enif_get_uint64(env, head, &input[i].uinteger64))
				return error_result(env, "parameter should be uint64");
			break;
		case TYPE_DOUBLE:
			if (!enif_get_double(env, head, &input[i].doubleval))
				return error_result(env, "parameter should be double");
			break;
		// case TYPE_STRING:
		case TYPE_BINARY:
		{
			ErlNifBinary erlbin;
			if (!enif_inspect_binary(env, head, &erlbin))
				return error_result(env, "parameter should be binary");
			input[i].binary.size = erlbin.size;
			input[i].binary.data = erlbin.data;
			break;
		}
		default:
			return error_result(env, "internal type error");
		}
	}

	Env user_env;
	user_env.method = method_index;
	user_env.head = 0;
	const char *error = program->runop(&user_env, input, output);
	if (error)
	{
		free_env(&user_env);
		return error_result(env, error);
	}

	ERL_NIF_TERM ret = enif_make_list(env, 0);
	for (int i = 0; i < method->outputs.size; i++)
	{
		ERL_NIF_TERM cell;
		Param *param = output + i;

		switch (method->outputs.params[i].type)
		{
		case TYPE_INT64:
			cell = enif_make_int64(env, param->integer64);
			break;
		case TYPE_UINT64:
			cell = enif_make_uint64(env, param->uinteger64);
			break;
		case TYPE_DOUBLE:
			cell = enif_make_double(env, param->doubleval);
			break;
		// case TYPE_STRING:
		case TYPE_BINARY:
		{
			unsigned char *bin = enif_make_new_binary(env, param->binary.size, &cell);
			if (!bin)
			{
				free_env(&user_env);
				return error_result(env, "could not allocate result binary");
			}

			memcpy(bin, param->binary.data, param->binary.size);
			break;
		}
		default:
			free_env(&user_env);
			return error_result(env, "internal type error");
		}
		ret = enif_make_list_cell(env, cell, ret);
	}

	free_env(&user_env);
	return ok_result(env, ret);
}

static ERL_NIF_TERM error_result(ErlNifEnv *env, const char *error_msg)
{
	ERL_NIF_TERM bin;
	unsigned char *dst = enif_make_new_binary(env, strlen(error_msg), &bin);
	memcpy(dst, error_msg, strlen(error_msg));
	return enif_make_tuple2(env, enif_make_atom(env, "error"), bin);
}

static ERL_NIF_TERM ok_result(ErlNifEnv *env, ERL_NIF_TERM ret)
{
	return enif_make_tuple2(env, enif_make_atom(env, "ok"), ret);
}

static ErlNifFunc nif_funcs[] = {
	{"nif_compile", 2, compile},
	{"nif_run", 3, run}};

ERL_NIF_INIT(Elixir.Niffler, nif_funcs, &load, NULL, &upgrade, &unload);

/* Copyright, 2021 Dominic Letz */

#include <string.h>
#include <stdint.h>
#include "erl_nif.h"
#include "tinycc/libtcc.h"

static ERL_NIF_TERM error_result(ErlNifEnv *env, char *error_msg);
static ERL_NIF_TERM ok_result(ErlNifEnv *env, ERL_NIF_TERM ret);
static void free_state(ErlNifEnv *env, void *obj);

static ErlNifResourceType *PROGRAM_TYPE;

struct Binary
{
	uint64_t size;
	unsigned char *data;
};

struct Param
{
	char name[64];
	int type;
	int size;
	// No member can be larger than *symbol or it will get lost in assignment
	union
	{
		void *symbol;
		char *string;
		struct Binary *binary;
		int64_t integer64;
		uint64_t uinteger64;
		double doubleval;
	};
};

#define TYPE_INT64 1
#define TYPE_UINT64 2
// #define TYPE_STRING 4
#define TYPE_BINARY 5
#define TYPE_DOUBLE 6

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

struct Params
{
	unsigned size;
	struct Param *params;
};

struct Program
{
	TCCState *state;
	struct Params inputs;
	struct Params outputs;
};

static int
load(ErlNifEnv *env, void **priv, ERL_NIF_TERM load_info)
{
	int flags = ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER;
	PROGRAM_TYPE = enif_open_resource_type(env, "Elixir.Tinycc", "state", free_state, flags, NULL);
	if (PROGRAM_TYPE == 0)
	{
		return -1;
	}
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
scan_param(ErlNifEnv *env, ERL_NIF_TERM erlp, struct Param *p, unsigned size, ERL_NIF_TERM *ret)
{
	if (!size)
	{
		return 1;
	}

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

static struct Params
scan_params(ErlNifEnv *env, ERL_NIF_TERM erl_params, ERL_NIF_TERM *ret)
{
	struct Params params = {};
	if (!enif_get_list_length(env, erl_params, &params.size))
	{
		*ret = error_result(env, "parameter is not a list");
		return params;
	}

	if (!params.size)
	{
		*ret = error_result(env, "parameter list is empty");
		return params;
	}

	params.params = malloc(sizeof(params.params[0]) * params.size);
	if (!params.params)
	{
		*ret = error_result(env, "could not allocate parameter list");
		return params;
	}

	if (!scan_param(env, erl_params, params.params, params.size, ret))
	{
		free(params.params);
		params.size = 0;
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
	{
		return enif_make_badarg(env);
	}

	ERL_NIF_TERM ret = error_result(env, "failed to scan input parameters");
	struct Params inputs = scan_params(env, argv[1], &ret);
	if (!inputs.size)
	{
		return ret;
	}
	ret = error_result(env, "failed to scan output parameters");
	struct Params outputs = scan_params(env, argv[2], &ret);
	if (!outputs.size)
	{
		free(inputs.params);
		return ret;
	}

	state = tcc_new();
	if (!state)
	{
		free(outputs.params);
		free(inputs.params);
		return error_result(env, "could not initiate tcc state");
	}

	struct Program *program = enif_alloc_resource(PROGRAM_TYPE, sizeof(struct Program));
	program->state = state;
	program->inputs = inputs;
	program->outputs = outputs;

	ERL_NIF_TERM term = enif_make_resource(env, program);
	enif_release_resource(program);

	if (tcc_set_output_type(state, TCC_OUTPUT_MEMORY) != 0)
	{
		return error_result(env, "could not set tcc output type");
	}

	if (tcc_compile_string(state, (const char *)sourcecode.data) != 0)
	{
		return error_result(env, "compilation error");
	}

	for (int i = 0; i < inputs.size; i++)
	{
		tcc_add_symbol(state, inputs.params[i].name, &inputs.params[i].string);
	}

	tcc_set_options(state, "-nostdlib");
	if (tcc_relocate(state, TCC_RELOCATE_AUTO) != 0)
	{
		return error_result(env, "could not relocate program");
	}

	return ok_result(env, term);
}

static void free_state(ErlNifEnv *env, void *obj)
{
	struct Program *program = (struct Program *)obj;
	tcc_delete(program->state);
	free(program->inputs.params);
	free(program->outputs.params);
}

static ERL_NIF_TERM
run(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
	struct Program *program;

	if (!enif_get_resource(env, argv[0], PROGRAM_TYPE, (void *)&program))
	{
		return enif_make_badarg(env);
	}

	ERL_NIF_TERM head, tail = argv[1];
	struct Binary bin;

	for (int i = 0; i < program->inputs.size; i++)
	{
		if (!enif_get_list_cell(env, tail, &head, &tail))
		{
			return error_result(env, "not enough arguments");
		}

		switch (program->inputs.params[i].type)
		{
		case TYPE_INT64:
			if (!enif_get_int64(env, head, &program->inputs.params[i].integer64))
			{
				return error_result(env, "parameter should be int64");
			}
			break;
		case TYPE_UINT64:
			if (!enif_get_uint64(env, head, &program->inputs.params[i].uinteger64))
			{
				return error_result(env, "parameter should be uint64");
			}
			break;
		case TYPE_DOUBLE:
			if (!enif_get_double(env, head, &program->inputs.params[i].doubleval))
			{
				return error_result(env, "parameter should be double");
			}
			break;
		// case TYPE_STRING:
		case TYPE_BINARY:
		{
			ErlNifBinary erlbin;
			if (!enif_inspect_binary(env, head, &erlbin))
			{
				return error_result(env, "parameter should be binary");
			}
			bin.size = erlbin.size;
			bin.data = erlbin.data;
			program->inputs.params[i].binary = &bin;
			break;
		}
		default:
			return error_result(env, "internal type error");
		}
	}

	int (*const runop)() = tcc_get_symbol(program->state, "run");

	if (!runop)
	{
		return error_result(env, "run operation not defined");
	}

	runop();

	ERL_NIF_TERM ret = enif_make_list(env, 0);
	for (int i = 0; i < program->outputs.size; i++)
	{
		ERL_NIF_TERM cell;
		struct Param *param = program->outputs.params + i;

		param->symbol = tcc_get_symbol(program->state, param->name);

		if (!param->symbol)
		{
			return error_result(env, "symbol not found");
		}

		switch (param->type)
		{
		case TYPE_INT64:
			cell = enif_make_int64(env, *(ErlNifSInt64 *)param->symbol);
			break;
		case TYPE_UINT64:
			cell = enif_make_uint64(env, *(ErlNifUInt64 *)param->symbol);
			break;
		case TYPE_DOUBLE:
			cell = enif_make_double(env, *(double *)param->symbol);
			break;
		// case TYPE_STRING:
		case TYPE_BINARY:
		{
			if (!param->binary)
			{
				return error_result(env, "returned 0 binary");
			}

			unsigned char *bin = enif_make_new_binary(env, param->binary->size, &cell);
			if (!bin)
			{
				return error_result(env, "could not allocate result binary");
			}

			memcpy(bin, param->binary->data, param->binary->size);
			break;
		}
		default:
			return error_result(env, "internal type error");
		}
		ret = enif_make_list_cell(env, cell, ret);
	}

	return ok_result(env, ret);
}

#define GET_SYMBOL()                                                    \
	void *symbol = 0;                                                   \
	{                                                                   \
		ERL_NIF_TERM term = get_symbol(env, argv[0], argv[1], &symbol); \
		if (!symbol)                                                    \
			return term;                                                \
	}

static ERL_NIF_TERM
get_symbol(
	ErlNifEnv *env, ERL_NIF_TERM state_arg, ERL_NIF_TERM var_arg,
	void **symbol)
{
	ErlNifBinary varname;
	TCCState *state;
	char symbol_name[255];

	if (!enif_get_resource(env, state_arg, PROGRAM_TYPE, (void **)&state))
	{
		return enif_make_badarg(env);
	}

	if (!enif_inspect_binary(env, var_arg, &varname))
	{
		return enif_make_badarg(env);
	}

	if (varname.size >= sizeof(symbol_name))
	{
		return error_result(env, "symbol name too long");
	}

	memcpy(symbol_name, varname.data, varname.size);
	symbol_name[varname.size] = 0;

	*symbol = tcc_get_symbol(state, (const char *)varname.data);

	if (!*symbol)
	{
		return error_result(env, "can't find symbol");
	}

	ERL_NIF_TERM none = 0;
	return none;
}

static ERL_NIF_TERM
get_string(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
	GET_SYMBOL();

	char *value = (char *)symbol;
	ERL_NIF_TERM ret;
	unsigned char *data = enif_make_new_binary(env, strlen(value), &ret);

	if (!data)
	{
		return error_result(env, "couldn't create a binary");
	}

	memcpy(data, value, strlen(value));
	return ok_result(env, ret);
}

static ERL_NIF_TERM
get_data(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
	GET_SYMBOL();

	int *size = 0;
	if (!enif_get_int(env, argv[2], size))
	{
		return enif_make_badarg(env);
	}

	if (*size < 0)
	{
		return enif_make_badarg(env);
	}

	char *value = (char *)symbol;
	ERL_NIF_TERM ret;
	unsigned char *data = enif_make_new_binary(env, *size, &ret);

	if (!data)
	{
		return error_result(env, "couldn't create a binary");
	}

	memcpy(data, value, *size);
	return ok_result(env, ret);
}

static ERL_NIF_TERM
get_int(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
	GET_SYMBOL();
	int *value = (int *)symbol;
	return enif_make_int(env, *value);
}

static ERL_NIF_TERM
get_int64(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
	GET_SYMBOL();
	ErlNifSInt64 *value = (ErlNifSInt64 *)symbol;
	return enif_make_int64(env, *value);
}

static ERL_NIF_TERM
get_uint64(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
	GET_SYMBOL();
	ErlNifUInt64 *value = (ErlNifUInt64 *)symbol;
	return enif_make_int64(env, *value);
}

static ERL_NIF_TERM error_result(ErlNifEnv *env, char *error_msg)
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
	{"nif_compile", 3, compile},
	{"nif_run", 2, run}
	// {"get_string", 2, get_string},
	// {"get_data", 3, get_data},
	// {"get_uint64", 2, get_uint64},
	// {"get_int64", 2, get_int64},
	// {"get_int", 2, get_int}

};

ERL_NIF_INIT(Elixir.Tinycc, nif_funcs, &load, NULL, &upgrade, &unload);

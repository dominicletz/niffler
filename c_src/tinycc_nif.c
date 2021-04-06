/* Copyright, 2021 Dominic Letz */

#include "erl_nif.h"
#include "libtcc.h"

static ERL_NIF_TERM atom_from_result(ErlNifEnv* env, int res);
static ERL_NIF_TERM error_result(ErlNifEnv* env, char* error_msg);
static ERL_NIF_TERM ok_result(ErlNifEnv* env, ERL_NIF_TERM *r);
int get_compressed_flag(ErlNifEnv* env, ERL_NIF_TERM arg, int* compressed, size_t* pubkeylen);
int check_compressed(size_t Size);
int get_nonce_function(ErlNifEnv* env, ERL_NIF_TERM nonce_term, ERL_NIF_TERM nonce_data_term, secp256k1_nonce_function* noncefp, ErlNifBinary* noncedata);
int get_recid(ErlNifEnv* env, ERL_NIF_TERM argv, int* recid); 

// static TCCState* state = 0;

static int
load(ErlNifEnv* env, void** priv, ERL_NIF_TERM load_info)
{
    return 0;
}

static int
upgrade(ErlNifEnv* env, void** priv, void** old_priv, ERL_NIF_TERM load_info)
{
    return 0;
}

static void
unload(ErlNifEnv* env, void* priv)
{
    return;
}

static ERL_NIF_TERM
compile(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
	ErlNifBinary program;
	TCCState* state;

	if (!enif_inspect_binary(env, argv[0], &program)) {
       return enif_make_badarg(env);
    }

	state = tcc_new();
	if (!state) {
		return enif_make_badarg(env);
	}
	
    tcc_set_output_type(state, TCC_OUTPUT_MEMORY);

    if (tcc_compile_string(state, program.data) > 0) {
        // printf("Compilation error !\n");
		return enif_make_badarg(env);
    }

    tcc_relocate(state, TCC_RELOCATE_AUTO);
	return enif_make_resource()
}

static ERL_NIF_TERM
run(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
	ErlNifBinary program;
	TCCState* state;

	if (!enif_inspect_binary(env, argv[0], &program)) {
       return enif_make_badarg(env);
    }

	state = tcc_new();
	if (!state) {
		return error_result(env, "couldn't create tcc context");
	}
	
    tcc_set_output_type(state, TCC_OUTPUT_MEMORY);

    if (tcc_compile_string(state, program.data) > 0) {
		return return error_result(env, "compilation error");
    }

    tcc_relocate(s, TCC_RELOCATE_AUTO);

	return enif_make_resource()
}

static ERL_NIF_TERM error_result(ErlNifEnv* env, char* error_msg)
{
    return enif_make_tuple2(env, enif_make_atom(env, "error"), enif_make_string(env, error_msg, ERL_NIF_LATIN1));
}

static ERL_NIF_TERM ok_result(ErlNifEnv* env, ERL_NIF_TERM *r)
{
    return enif_make_tuple2(env, enif_make_atom(env, "ok"), *r);
}


static ErlNifFunc nif_funcs[] = {
	{"compile", 1, compile},
    {"run", 1, run}

};

ERL_NIF_INIT(tinycc, nif_funcs, &load, NULL, &upgrade, &unload);

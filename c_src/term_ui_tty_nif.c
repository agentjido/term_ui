/*
 * Disable terminal-driver handling of control bytes while a TermUI raw
 * session is active. OTP 28 and OTP 29 leave these controls enabled.
 *
 * The returned token contains only the flags that this NIF owns. Restore
 * merges those saved values into the current terminal mode so it does not
 * overwrite settings that another terminal layer owns.
 */

#include <erl_nif.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <errno.h>
#include <termios.h>
#include <unistd.h>
#endif

static ERL_NIF_TERM atom_error;
static ERL_NIF_TERM atom_ok;
static ERL_NIF_TERM atom_posix;
static ERL_NIF_TERM atom_true;
static ERL_NIF_TERM atom_win32;

static int load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
    (void)priv_data;
    (void)load_info;

    atom_error = enif_make_atom(env, "error");
    atom_ok = enif_make_atom(env, "ok");
    atom_posix = enif_make_atom(env, "posix");
    atom_true = enif_make_atom(env, "true");
    atom_win32 = enif_make_atom(env, "win32");
    return 0;
}

static ERL_NIF_TERM make_error(ErlNifEnv *env, ERL_NIF_TERM platform,
                               unsigned long code) {
    ERL_NIF_TERM reason =
        enif_make_tuple2(env, platform, enif_make_uint64(env, code));
    return enif_make_tuple2(env, atom_error, reason);
}

static ERL_NIF_TERM make_token(ErlNifEnv *env, ErlNifUInt64 local_flags,
                              ErlNifUInt64 input_flags) {
    ERL_NIF_TERM token =
        enif_make_tuple2(env, enif_make_uint64(env, local_flags),
                         enif_make_uint64(env, input_flags));
    return enif_make_tuple2(env, atom_ok, token);
}

static int get_token(ErlNifEnv *env, ERL_NIF_TERM term,
                     ErlNifUInt64 *local_flags,
                     ErlNifUInt64 *input_flags) {
    int arity;
    const ERL_NIF_TERM *elements;

    return enif_get_tuple(env, term, &arity, &elements) && arity == 2 &&
           enif_get_uint64(env, elements[0], local_flags) &&
           enif_get_uint64(env, elements[1], input_flags);
}

static ERL_NIF_TERM loaded(ErlNifEnv *env, int argc,
                           const ERL_NIF_TERM argv[]) {
    (void)env;
    (void)argc;
    (void)argv;
    return atom_true;
}

#ifdef _WIN32

static ERL_NIF_TERM disable_control_flags(ErlNifEnv *env, int argc,
                                          const ERL_NIF_TERM argv[]) {
    HANDLE input;
    DWORD mode;
    DWORD saved;

    (void)argc;
    (void)argv;

    input = GetStdHandle(STD_INPUT_HANDLE);
    if (input == NULL || input == INVALID_HANDLE_VALUE) {
        return make_error(env, atom_win32, GetLastError());
    }
    if (!GetConsoleMode(input, &mode)) {
        return make_error(env, atom_win32, GetLastError());
    }

    saved = mode & ENABLE_PROCESSED_INPUT;
    if (!SetConsoleMode(input, mode & ~ENABLE_PROCESSED_INPUT)) {
        return make_error(env, atom_win32, GetLastError());
    }

    return make_token(env, saved, 0);
}

static ERL_NIF_TERM restore_control_flags(ErlNifEnv *env, int argc,
                                          const ERL_NIF_TERM argv[]) {
    ErlNifUInt64 saved;
    ErlNifUInt64 unused;
    HANDLE input;
    DWORD mode;

    if (argc != 1 || !get_token(env, argv[0], &saved, &unused)) {
        return enif_make_badarg(env);
    }

    input = GetStdHandle(STD_INPUT_HANDLE);
    if (input == NULL || input == INVALID_HANDLE_VALUE) {
        return make_error(env, atom_win32, GetLastError());
    }
    if (!GetConsoleMode(input, &mode)) {
        return make_error(env, atom_win32, GetLastError());
    }

    mode = (mode & ~ENABLE_PROCESSED_INPUT) |
           ((DWORD)saved & ENABLE_PROCESSED_INPUT);
    if (!SetConsoleMode(input, mode)) {
        return make_error(env, atom_win32, GetLastError());
    }

    return atom_ok;
}

#else

static tcflag_t controlled_local_flags(void) {
    tcflag_t flags = 0;

#ifdef ISIG
    flags |= ISIG;
#endif
#ifdef IEXTEN
    flags |= IEXTEN;
#endif

    return flags;
}

static tcflag_t controlled_input_flags(void) {
    tcflag_t flags = 0;

#ifdef IXON
    flags |= IXON;
#endif

    return flags;
}

static ERL_NIF_TERM disable_control_flags(ErlNifEnv *env, int argc,
                                          const ERL_NIF_TERM argv[]) {
    struct termios terminal;
    tcflag_t local_mask = controlled_local_flags();
    tcflag_t input_mask = controlled_input_flags();
    int error_number;

    (void)argc;
    (void)argv;

    if (tcgetattr(STDIN_FILENO, &terminal) != 0) {
        error_number = errno;
        return make_error(env, atom_posix, (unsigned long)error_number);
    }

    tcflag_t saved_local = terminal.c_lflag & local_mask;
    tcflag_t saved_input = terminal.c_iflag & input_mask;
    terminal.c_lflag &= ~local_mask;
    terminal.c_iflag &= ~input_mask;

    if (tcsetattr(STDIN_FILENO, TCSANOW, &terminal) != 0) {
        error_number = errno;
        return make_error(env, atom_posix, (unsigned long)error_number);
    }

    return make_token(env, (ErlNifUInt64)saved_local,
                      (ErlNifUInt64)saved_input);
}

static ERL_NIF_TERM restore_control_flags(ErlNifEnv *env, int argc,
                                          const ERL_NIF_TERM argv[]) {
    ErlNifUInt64 saved_local;
    ErlNifUInt64 saved_input;
    struct termios terminal;
    tcflag_t local_mask = controlled_local_flags();
    tcflag_t input_mask = controlled_input_flags();
    int error_number;

    if (argc != 1 ||
        !get_token(env, argv[0], &saved_local, &saved_input)) {
        return enif_make_badarg(env);
    }

    if (tcgetattr(STDIN_FILENO, &terminal) != 0) {
        error_number = errno;
        return make_error(env, atom_posix, (unsigned long)error_number);
    }

    terminal.c_lflag =
        (terminal.c_lflag & ~local_mask) |
        ((tcflag_t)saved_local & local_mask);
    terminal.c_iflag =
        (terminal.c_iflag & ~input_mask) |
        ((tcflag_t)saved_input & input_mask);

    if (tcsetattr(STDIN_FILENO, TCSANOW, &terminal) != 0) {
        error_number = errno;
        return make_error(env, atom_posix, (unsigned long)error_number);
    }

    return atom_ok;
}

#endif

static ErlNifFunc nif_functions[] = {
    {"loaded?", 0, loaded, 0},
    {"disable_control_flags", 0, disable_control_flags, 0},
    {"restore_control_flags", 1, restore_control_flags, 0}
};

ERL_NIF_INIT(Elixir.TermUI.Terminal.TtyNif, nif_functions, load, NULL, NULL,
             NULL)

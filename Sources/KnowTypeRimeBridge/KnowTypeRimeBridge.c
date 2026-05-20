#include "KnowTypeRimeBridge.h"

#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef uintptr_t RimeSessionId;
typedef bool Bool;

typedef struct {
    int data_size;
    const char *shared_data_dir;
    const char *user_data_dir;
    const char *distribution_name;
    const char *distribution_code_name;
    const char *distribution_version;
    const char *app_name;
    const char **modules;
    int min_log_level;
    const char *log_dir;
    const char *prebuilt_data_dir;
    const char *staging_dir;
} RimeTraits;

typedef struct {
    int length;
    int cursor_pos;
    int sel_start;
    int sel_end;
    char *preedit;
} RimeComposition;

typedef struct {
    char *text;
    char *comment;
    void *reserved;
} RimeCandidate;

typedef struct {
    int page_size;
    int page_no;
    Bool is_last_page;
    int highlighted_candidate_index;
    int num_candidates;
    RimeCandidate *candidates;
    char *select_keys;
} RimeMenu_stdbool;

typedef struct {
    int data_size;
    char *text;
} RimeCommit;

typedef struct {
    int data_size;
    RimeComposition composition;
    RimeMenu_stdbool menu;
    char *commit_text_preview;
    char **select_labels;
} RimeContext_stdbool;

typedef struct {
    int data_size;
    char *schema_id;
    char *schema_name;
    Bool is_disabled;
    Bool is_composing;
    Bool is_ascii_mode;
    Bool is_full_shape;
    Bool is_simplified;
    Bool is_traditional;
    Bool is_ascii_punct;
} RimeStatus_stdbool;

typedef struct {
    void *ptr;
    int index;
    RimeCandidate candidate;
} RimeCandidateListIterator;

typedef struct {
    void *ptr;
} RimeConfig;

typedef struct {
    void *list;
    void *map;
    int index;
    const char *key;
    const char *path;
} RimeConfigIterator;

typedef struct {
    char *schema_id;
    char *name;
    void *reserved;
} RimeSchemaListItem;

typedef struct {
    size_t size;
    RimeSchemaListItem *list;
} RimeSchemaList;

typedef struct {
    const char *str;
    size_t length;
} RimeStringSlice;

typedef void (*RimeNotificationHandler)(void *, RimeSessionId, const char *, const char *);

typedef struct {
    int data_size;
} RimeCustomApi;

typedef struct {
    int data_size;
    const char *module_name;
    void (*initialize)(void);
    void (*finalize)(void);
    RimeCustomApi *(*get_api)(void);
} RimeModule;

typedef struct {
    int data_size;
    void (*setup)(RimeTraits *traits);
    void (*set_notification_handler)(RimeNotificationHandler handler, void *context_object);
    void (*initialize)(RimeTraits *traits);
    void (*finalize)(void);
    Bool (*start_maintenance)(Bool full_check);
    Bool (*is_maintenance_mode)(void);
    void (*join_maintenance_thread)(void);
    void (*deployer_initialize)(RimeTraits *traits);
    Bool (*prebuild)(void);
    Bool (*deploy)(void);
    Bool (*deploy_schema)(const char *schema_file);
    Bool (*deploy_config_file)(const char *file_name, const char *version_key);
    Bool (*sync_user_data)(void);
    RimeSessionId (*create_session)(void);
    Bool (*find_session)(RimeSessionId session_id);
    Bool (*destroy_session)(RimeSessionId session_id);
    void (*cleanup_stale_sessions)(void);
    void (*cleanup_all_sessions)(void);
    Bool (*process_key)(RimeSessionId session_id, int keycode, int mask);
    Bool (*commit_composition)(RimeSessionId session_id);
    void (*clear_composition)(RimeSessionId session_id);
    Bool (*get_commit)(RimeSessionId session_id, RimeCommit *commit);
    Bool (*free_commit)(RimeCommit *commit);
    Bool (*get_context)(RimeSessionId session_id, RimeContext_stdbool *context);
    Bool (*free_context)(RimeContext_stdbool *ctx);
    Bool (*get_status)(RimeSessionId session_id, RimeStatus_stdbool *status);
    Bool (*free_status)(RimeStatus_stdbool *status);
    void (*set_option)(RimeSessionId session_id, const char *option, Bool value);
    Bool (*get_option)(RimeSessionId session_id, const char *option);
    void (*set_property)(RimeSessionId session_id, const char *prop, const char *value);
    Bool (*get_property)(RimeSessionId session_id, const char *prop, char *value, size_t buffer_size);
    Bool (*get_schema_list)(RimeSchemaList *schema_list);
    void (*free_schema_list)(RimeSchemaList *schema_list);
    Bool (*get_current_schema)(RimeSessionId session_id, char *schema_id, size_t buffer_size);
    Bool (*select_schema)(RimeSessionId session_id, const char *schema_id);
    Bool (*schema_open)(const char *schema_id, RimeConfig *config);
    Bool (*config_open)(const char *config_id, RimeConfig *config);
    Bool (*config_close)(RimeConfig *config);
    Bool (*config_get_bool)(RimeConfig *config, const char *key, Bool *value);
    Bool (*config_get_int)(RimeConfig *config, const char *key, int *value);
    Bool (*config_get_double)(RimeConfig *config, const char *key, double *value);
    Bool (*config_get_string)(RimeConfig *config, const char *key, char *value, size_t buffer_size);
    const char *(*config_get_cstring)(RimeConfig *config, const char *key);
    Bool (*config_update_signature)(RimeConfig *config, const char *signer);
    Bool (*config_begin_map)(RimeConfigIterator *iterator, RimeConfig *config, const char *key);
    Bool (*config_next)(RimeConfigIterator *iterator);
    void (*config_end)(RimeConfigIterator *iterator);
    Bool (*simulate_key_sequence)(RimeSessionId session_id, const char *key_sequence);
    Bool (*register_module)(RimeModule *module);
    RimeModule *(*find_module)(const char *module_name);
    Bool (*run_task)(const char *task_name);
    const char *(*get_shared_data_dir)(void);
    const char *(*get_user_data_dir)(void);
    const char *(*get_sync_dir)(void);
    const char *(*get_user_id)(void);
    void (*get_user_data_sync_dir)(char *dir, size_t buffer_size);
    Bool (*config_init)(RimeConfig *config);
    Bool (*config_load_string)(RimeConfig *config, const char *yaml);
    Bool (*config_set_bool)(RimeConfig *config, const char *key, Bool value);
    Bool (*config_set_int)(RimeConfig *config, const char *key, int value);
    Bool (*config_set_double)(RimeConfig *config, const char *key, double value);
    Bool (*config_set_string)(RimeConfig *config, const char *key, const char *value);
    Bool (*config_get_item)(RimeConfig *config, const char *key, RimeConfig *value);
    Bool (*config_set_item)(RimeConfig *config, const char *key, RimeConfig *value);
    Bool (*config_clear)(RimeConfig *config, const char *key);
    Bool (*config_create_list)(RimeConfig *config, const char *key);
    Bool (*config_create_map)(RimeConfig *config, const char *key);
    size_t (*config_list_size)(RimeConfig *config, const char *key);
    Bool (*config_begin_list)(RimeConfigIterator *iterator, RimeConfig *config, const char *key);
    const char *(*get_input)(RimeSessionId session_id);
    size_t (*get_caret_pos)(RimeSessionId session_id);
    Bool (*select_candidate)(RimeSessionId session_id, size_t index);
    const char *(*get_version)(void);
    void (*set_caret_pos)(RimeSessionId session_id, size_t caret_pos);
    Bool (*select_candidate_on_current_page)(RimeSessionId session_id, size_t index);
    Bool (*candidate_list_begin)(RimeSessionId session_id, RimeCandidateListIterator *iterator);
    Bool (*candidate_list_next)(RimeCandidateListIterator *iterator);
    void (*candidate_list_end)(RimeCandidateListIterator *iterator);
    Bool (*user_config_open)(const char *config_id, RimeConfig *config);
    Bool (*candidate_list_from_index)(RimeSessionId session_id, RimeCandidateListIterator *iterator, int index);
    const char *(*get_prebuilt_data_dir)(void);
    const char *(*get_staging_dir)(void);
    void (*commit_proto)(RimeSessionId session_id, void *commit_builder);
    void (*context_proto)(RimeSessionId session_id, void *context_builder);
    void (*status_proto)(RimeSessionId session_id, void *status_builder);
    const char *(*get_state_label)(RimeSessionId session_id, const char *option_name, Bool state);
    Bool (*delete_candidate)(RimeSessionId session_id, size_t index);
    Bool (*delete_candidate_on_current_page)(RimeSessionId session_id, size_t index);
    RimeStringSlice (*get_state_label_abbreviated)(RimeSessionId session_id, const char *option_name, Bool state, Bool abbreviated);
    Bool (*set_input)(RimeSessionId session_id, const char *input);
    void (*get_shared_data_dir_s)(char *dir, size_t buffer_size);
    void (*get_user_data_dir_s)(char *dir, size_t buffer_size);
    void (*get_prebuilt_data_dir_s)(char *dir, size_t buffer_size);
    void (*get_staging_dir_s)(char *dir, size_t buffer_size);
    void (*get_sync_dir_s)(char *dir, size_t buffer_size);
    Bool (*highlight_candidate)(RimeSessionId session_id, size_t index);
    Bool (*highlight_candidate_on_current_page)(RimeSessionId session_id, size_t index);
    Bool (*change_page)(RimeSessionId session_id, Bool backward);
} RimeApi_stdbool;

typedef RimeApi_stdbool *(*RimeGetApiFunction)(void);

struct KTBRimeSession {
    void *library_handle;
    RimeApi_stdbool *api;
    RimeSessionId session_id;
};

static bool ktb_rime_initialized = false;
static void *ktb_rime_library_handle = NULL;
static RimeApi_stdbool *ktb_rime_api = NULL;

static void ktb_rime_traits_init(RimeTraits *traits) {
    memset(traits, 0, sizeof(RimeTraits));
    traits->data_size = (int)(sizeof(RimeTraits) - sizeof(traits->data_size));
}

static void ktb_rime_commit_init(RimeCommit *commit) {
    memset(commit, 0, sizeof(RimeCommit));
    commit->data_size = (int)(sizeof(RimeCommit) - sizeof(commit->data_size));
}

static void ktb_rime_context_init(RimeContext_stdbool *context) {
    memset(context, 0, sizeof(RimeContext_stdbool));
    context->data_size = (int)(sizeof(RimeContext_stdbool) - sizeof(context->data_size));
}

static char *ktb_strdup(const char *value) {
    if (!value) {
        return NULL;
    }
    size_t length = strlen(value);
    char *copy = (char *)malloc(length + 1);
    if (!copy) {
        return NULL;
    }
    memcpy(copy, value, length + 1);
    return copy;
}

KTBRimeSession *ktb_rime_session_create(
    const char *library_path,
    const char *shared_data_dir,
    const char *user_data_dir,
    const char *log_dir,
    const char *distribution_version,
    const char *app_name,
    const char *schema_id
) {
    if (!library_path || !shared_data_dir || !user_data_dir) {
        return NULL;
    }

    void *handle = ktb_rime_library_handle;
    RimeApi_stdbool *api = ktb_rime_api;
    bool owns_new_handle = false;
    if (!handle || !api) {
        handle = dlopen(library_path, RTLD_NOW | RTLD_LOCAL);
        if (!handle) {
            return NULL;
        }
        owns_new_handle = true;

        RimeGetApiFunction get_api = (RimeGetApiFunction)dlsym(handle, "rime_get_api_stdbool");
        if (!get_api) {
            dlclose(handle);
            return NULL;
        }
        api = get_api();
    }
    if (!api || !api->setup || !api->initialize || !api->create_session ||
        !api->process_key || !api->get_commit || !api->free_commit ||
        !api->get_context || !api->free_context || !api->destroy_session) {
        if (owns_new_handle) {
            dlclose(handle);
        }
        return NULL;
    }

    RimeTraits traits;
    ktb_rime_traits_init(&traits);
    traits.shared_data_dir = shared_data_dir;
    traits.user_data_dir = user_data_dir;
    traits.log_dir = log_dir;
    traits.distribution_name = "KnowType";
    traits.distribution_code_name = "KnowType";
    traits.distribution_version = distribution_version ? distribution_version : "0";
    traits.app_name = app_name ? app_name : "rime.knowtype";
    traits.min_log_level = 1;

    if (!ktb_rime_initialized) {
        api->setup(&traits);
        api->initialize(NULL);
        if (api->start_maintenance) {
            api->start_maintenance(false);
        }
        if (api->join_maintenance_thread) {
            api->join_maintenance_thread();
        }
        ktb_rime_library_handle = handle;
        ktb_rime_api = api;
        ktb_rime_initialized = true;
    }

    RimeSessionId session_id = api->create_session();
    if (session_id == 0) {
        if (owns_new_handle && !ktb_rime_library_handle) {
            dlclose(handle);
        }
        return NULL;
    }
    if (schema_id && schema_id[0] != '\0' && api->select_schema) {
        api->select_schema(session_id, schema_id);
    }

    KTBRimeSession *session = (KTBRimeSession *)calloc(1, sizeof(KTBRimeSession));
    if (!session) {
        api->destroy_session(session_id);
        if (owns_new_handle && !ktb_rime_library_handle) {
            dlclose(handle);
        }
        return NULL;
    }
    session->library_handle = handle;
    session->api = api;
    session->session_id = session_id;
    return session;
}

void ktb_rime_session_destroy(KTBRimeSession *session) {
    if (!session) {
        return;
    }
    if (session->api && session->session_id != 0 && session->api->destroy_session) {
        session->api->destroy_session(session->session_id);
    }
    // Rime owns process-global state after initialize(). Mature IMK hosts keep
    // librime loaded until process exit; unloading on every session reset can
    // leave ktb_rime_initialized true while the dynamic library state is gone.
    free(session);
}

bool ktb_rime_process_key(KTBRimeSession *session, int keycode, int mask) {
    if (!session || !session->api || !session->api->process_key || session->session_id == 0) {
        return false;
    }
    return session->api->process_key(session->session_id, keycode, mask);
}

void ktb_rime_clear_composition(KTBRimeSession *session) {
    if (!session || !session->api || !session->api->clear_composition || session->session_id == 0) {
        return;
    }
    session->api->clear_composition(session->session_id);
}

char *ktb_rime_copy_commit(KTBRimeSession *session) {
    if (!session || !session->api || !session->api->get_commit || !session->api->free_commit) {
        return NULL;
    }
    RimeCommit commit;
    ktb_rime_commit_init(&commit);
    if (!session->api->get_commit(session->session_id, &commit)) {
        return NULL;
    }
    char *copy = ktb_strdup(commit.text);
    session->api->free_commit(&commit);
    return copy;
}

KTBRimeContextSnapshot *ktb_rime_copy_context(KTBRimeSession *session) {
    if (!session || !session->api || !session->api->get_context || !session->api->free_context) {
        return NULL;
    }

    RimeContext_stdbool context;
    ktb_rime_context_init(&context);
    if (!session->api->get_context(session->session_id, &context)) {
        return NULL;
    }

    KTBRimeContextSnapshot *snapshot = (KTBRimeContextSnapshot *)calloc(1, sizeof(KTBRimeContextSnapshot));
    if (!snapshot) {
        session->api->free_context(&context);
        return NULL;
    }

    snapshot->preedit = ktb_strdup(context.composition.preedit);
    snapshot->commit_text_preview = ktb_strdup(context.commit_text_preview);
    snapshot->highlighted_candidate_index = context.menu.highlighted_candidate_index;
    snapshot->page_size = context.menu.page_size;
    snapshot->page_no = context.menu.page_no;
    snapshot->is_last_page = context.menu.is_last_page;

    int count = context.menu.num_candidates;
    if (count < 0) {
        count = 0;
    }
    snapshot->candidate_count = (size_t)count;
    if (snapshot->candidate_count > 0) {
        snapshot->candidates = (KTBRimeCandidateSnapshot *)calloc(snapshot->candidate_count, sizeof(KTBRimeCandidateSnapshot));
        if (!snapshot->candidates) {
            snapshot->candidate_count = 0;
        } else {
            for (size_t index = 0; index < snapshot->candidate_count; index += 1) {
                snapshot->candidates[index].text = ktb_strdup(context.menu.candidates[index].text);
                snapshot->candidates[index].comment = ktb_strdup(context.menu.candidates[index].comment);
            }
        }
    }

    session->api->free_context(&context);
    return snapshot;
}

void ktb_rime_context_snapshot_free(KTBRimeContextSnapshot *snapshot) {
    if (!snapshot) {
        return;
    }
    free(snapshot->preedit);
    free(snapshot->commit_text_preview);
    if (snapshot->candidates) {
        for (size_t index = 0; index < snapshot->candidate_count; index += 1) {
            free(snapshot->candidates[index].text);
            free(snapshot->candidates[index].comment);
        }
        free(snapshot->candidates);
    }
    free(snapshot);
}

bool ktb_rime_select_candidate_on_current_page(KTBRimeSession *session, size_t index) {
    if (!session || !session->api || !session->api->select_candidate_on_current_page) {
        return false;
    }
    return session->api->select_candidate_on_current_page(session->session_id, index);
}

bool ktb_rime_change_page(KTBRimeSession *session, bool backward) {
    if (!session || !session->api || !session->api->change_page) {
        return false;
    }
    return session->api->change_page(session->session_id, backward);
}

void ktb_rime_string_free(char *value) {
    free(value);
}

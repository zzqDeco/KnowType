#ifndef KNOWTYPE_RIME_BRIDGE_H
#define KNOWTYPE_RIME_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KTBRimeSession KTBRimeSession;

typedef struct {
    int index;
    char *text;
    char *comment;
} KTBRimeCandidateSnapshot;

typedef struct {
    char *raw_input;
    char *preedit;
    char *commit_text_preview;
    int highlighted_candidate_index;
    int page_size;
    int page_no;
    bool is_last_page;
    size_t candidate_count;
    KTBRimeCandidateSnapshot *candidates;
} KTBRimeContextSnapshot;

KTBRimeSession *ktb_rime_session_create(
    const char *library_path,
    const char *shared_data_dir,
    const char *user_data_dir,
    const char *log_dir,
    const char *distribution_version,
    const char *app_name,
    const char *schema_id
);

void ktb_rime_session_destroy(KTBRimeSession *session);

bool ktb_rime_process_key(KTBRimeSession *session, int keycode, int mask);

void ktb_rime_clear_composition(KTBRimeSession *session);

bool ktb_rime_commit_composition(KTBRimeSession *session);

char *ktb_rime_copy_commit(KTBRimeSession *session);

KTBRimeContextSnapshot *ktb_rime_copy_context(KTBRimeSession *session);

void ktb_rime_context_snapshot_free(KTBRimeContextSnapshot *snapshot);

bool ktb_rime_select_candidate_on_current_page(KTBRimeSession *session, size_t index);

bool ktb_rime_select_candidate(KTBRimeSession *session, size_t index);

bool ktb_rime_highlight_candidate_on_current_page(KTBRimeSession *session, size_t index);

bool ktb_rime_change_page(KTBRimeSession *session, bool backward);

bool ktb_rime_sync_user_data(KTBRimeSession *session);

char *ktb_rime_copy_user_data_dir(KTBRimeSession *session);

char *ktb_rime_copy_user_data_sync_dir(KTBRimeSession *session);

char *ktb_rime_copy_current_schema(KTBRimeSession *session);

char *ktb_rime_copy_schema_user_dict(KTBRimeSession *session, const char *schema_id);

void ktb_rime_string_free(char *value);

#ifdef __cplusplus
}
#endif

#endif

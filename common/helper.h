#ifndef MERGER_HELPER_H
#define MERGER_HELPER_H

#include <string>
#include <utility>

typedef enum { ASC_SORTED = 0, DESC_SORTED, RANDOM } SortType;

extern "C" {
// create a round of input/output vectors, return rid
uint32_t create_round(uint32_t sort_type);
void delete_round(uint32_t rid);

uint32_t add_seq(uint32_t rid, uint32_t seq_type, uint32_t n, uint32_t lower, uint32_t upper);
uint32_t move_seq(uint32_t rid_src, uint32_t rid_dst);

uint8_t check_invec(uint32_t rid, uint32_t sid);
uint32_t get_invec(uint32_t rid, uint32_t sid);
uint8_t check_outvec(uint32_t rid);
uint32_t get_outvec(uint32_t rid);
}

#endif

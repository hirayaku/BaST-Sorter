#include <cstdio>
#include <vector>
#include "helper.h"

int main(void)
{
    auto rid = create_round(ASC_SORTED);
    auto sid1 = add_seq(rid, RANDOM, 16, 0, 1024);
    auto sid2 = add_seq(rid, RANDOM, 16, 512, 1536);
    auto sid3 = add_seq(rid, RANDOM, 16, 512, 1536);

    uint32_t sum1 = 0, sum2 = 0, sum3 = 0, sum = 0;

    printf("Input vector 1: \n");
    while (check_invec(rid, sid1)) {
        auto item = get_invec(rid, sid1);
        sum1 += item;
        printf("%d ", item);
    }
    printf("\n");

    printf("Input vector 2: \n");
    while (check_invec(rid, sid2)) {
        auto item = get_invec(rid, sid2);
        sum2 += item;
        printf("%d ", item);
    }
    printf("\n");

    printf("Input vector 3: \n");
    while (check_invec(rid, sid3)) {
        auto item = get_invec(rid, sid3);
        sum3 += item;
        printf("%d ", item);
    }
    printf("\n");

    printf("Output vector: \n");
    while (check_outvec(rid)) {
        auto item = get_outvec(rid);
        sum += item;
        printf("%d ", item);
    }
    printf("\n");

    if (sum1 + sum2 + sum3 != sum) {
        fprintf(stderr, "Output vector is not correct!\n");
    }
    return 0;
}


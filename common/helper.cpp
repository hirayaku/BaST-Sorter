/*
 * Generate sort and merge datasets
 * Validate results of bsv simulation and this c++ program
 */

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <string>
#include <vector>
#include <iterator>
#include <algorithm>
#include <functional>
#include <utility>

#include "helper.h"

struct seq_config {
    size_t n;
    std::pair<uint32_t, uint32_t> bound;
    bool sorted;
    bool ascending;
    bool shuffle_full;
    int  shuffle_percent;
    size_t shuffle_block;
    std::string fname;
};

// Generate a sequence of random integers
// args:
// n                ->          length of the sequence
// min, max         ->          lower and upper bound of generated numbers
// sorted           ->          flag, whether the sequence will be sorted
// ascending        ->          flag, if sorted, whether the sequence will be increasingly or decreasingly sorted
static std::vector<uint32_t>
randseq(size_t n, std::pair<uint32_t, uint32_t> bound, bool sorted, bool ascending)
{
    std::vector<uint32_t> vec(n);
    std::random_device rd;
    std::mt19937 mt(rd());
    std::uniform_int_distribution<uint32_t> dist(bound.first, bound.second);

    std::generate(vec.begin(), vec.end(), std::bind(dist, std::ref(mt)));

    if (sorted) {
        if (ascending) {
            std::sort(vec.begin(), vec.end(), std::less<uint32_t>());
        } else {
            std::sort(vec.begin(), vec.end(), std::greater<uint32_t>());
        }
    }

    return vec;
}

// Shuffle a sequence of integers
// args:
// seq              ->          the sequence to shuffle
// block            ->          shuffle granularity
// percent          ->          #shuffle / (#blocks in seq)
static void
shuffle_partial(std::vector<uint32_t> &seq, size_t block, int percent)
{
    block = (block == 0) ? sizeof(uint32_t) : block;
    size_t seq_size = sizeof(uint32_t) * seq.size();
    assert(seq_size / block * block == seq_size); // sequence size is multiple of shuffle block size

    size_t block_l = block / sizeof(uint32_t);
    size_t block_n = seq_size / block;
    size_t shuffle_n = block_n * percent / 100;

    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<size_t> dist(0, block_n - 1);
    for (auto k = 0; k < shuffle_n; ++k) {
        auto i = dist(gen);
        auto j = dist(gen);
        if (i != j) {
            std::swap_ranges(seq.begin() + i * block_l, seq.begin() + (i+1) * block_l, seq.begin() + j * block_l);
        }
    }
}


// Fully shuffle a sequence of integers using Fisher-Yates
// args:
// seq              ->          the sequence to shuffle
// block            ->          shuffle granularity
static void
shuffle_full(std::vector<uint32_t> &seq, size_t block)
{
    block = (block == 0) ? sizeof(uint32_t) : block;
    size_t seq_size = sizeof(uint32_t) * seq.size();
    assert(seq_size / block * block == seq_size); // sequence size is multiple of shuffle block size

    size_t block_l = block / sizeof(uint32_t);
    size_t block_n = seq_size / block;

    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<size_t> dist;
    for (auto i = block_n - 1; i > 0; --i) {
        auto j = dist(gen) % (i + 1);
        if (i != j) {
            std::swap_ranges(seq.begin() + i * block_l, seq.begin() + (i+1) * block_l, seq.begin() + j * block_l);
        }
    }
}


// Generate two sorted sequences of integers and write them into files
// Merge the two sequences and write the result into a file
// args:
// fileA, fileB     ->          the files to write for the two sorted sequences
// fileO            ->          the file to write for the merged sequence
static void
gen_datafile(const seq_config &cfgA, const seq_config &cfgB, const seq_config &cfgO)
{
    auto fpA = std::fopen(cfgA.fname.data(), "wb");
    auto fpB = std::fopen(cfgB.fname.data(), "wb");
    auto fpO = std::fopen(cfgO.fname.data(), "wb");

    if (!(fpA && fpB && fpO)) {
        std::perror("gen_datafile: Cannot create certain data files\n");
        exit(EXIT_FAILURE);
    }

    std::vector<uint32_t> vecA = randseq(cfgA.n, cfgA.bound, cfgA.sorted, cfgA.ascending);
    if (cfgA.shuffle_full) {
        shuffle_full(vecA, cfgA.shuffle_block);
    } else if (cfgA.shuffle_percent != 0) {
        shuffle_partial(vecA, cfgA.shuffle_block, cfgA.shuffle_percent);
    }
    std::fwrite(vecA.data(), sizeof(vecA[0]), vecA.size(), fpA);
    std::fclose(fpA);

    std::vector<uint32_t> vecB = randseq(cfgB.n, cfgB.bound, cfgB.sorted, cfgB.ascending);
    if (cfgB.shuffle_full) {
        shuffle_full(vecB, cfgB.shuffle_block);
    } else if (cfgB.shuffle_percent != 0) {
        shuffle_partial(vecB, cfgB.shuffle_block, cfgB.shuffle_percent);
    }
    std::fwrite(vecB.data(), sizeof(vecB[0]), vecA.size(), fpB);
    std::fclose(fpB);

    if (!cfgA.sorted || cfgA.ascending != cfgO.ascending || cfgA.shuffle_full || cfgA.shuffle_percent != 0) {
        if (cfgO.ascending) {
            std::sort(vecA.begin(), vecA.end(), std::less<uint32_t>());
        } else {
            std::sort(vecA.begin(), vecA.end(), std::greater<uint32_t>());
        }
    }
    if (!cfgB.sorted || cfgB.ascending != cfgO.ascending || cfgB.shuffle_full || cfgB.shuffle_percent != 0) {
        if (cfgO.ascending) {
            std::sort(vecB.begin(), vecB.end(), std::less<uint32_t>());
        } else {
            std::sort(vecB.begin(), vecB.end(), std::greater<uint32_t>());
        }
    }

    std::vector<uint32_t> vecO;
    vecO.reserve(vecA.size() + vecB.size());
    if (cfgO.ascending) {
        std::merge(vecA.begin(), vecA.end(), vecB.begin(), vecB.end(), std::back_inserter(vecO), std::less<uint32_t>());
    } else {
        std::merge(vecA.begin(), vecA.end(), vecB.begin(), vecB.end(), std::back_inserter(vecO), std::greater<uint32_t>());
    }

    std::fwrite(vecO.data(), sizeof(vecO[0]), vecO.size(), fpO);
    std::fclose(fpO);
}


// Compare sequences in two files
// args:
// file1, file2     ->          two input files
static bool
cmp_datafile(std::string file1, std::string file2)
{
    auto fp1 = std::fopen(file1.data(), "rb");
    auto fp2 = std::fopen(file2.data(), "rb");
    if (!(fp1 && fp2)) {
        std::perror("cmp_datafile: Cannot open certain data files\n");
        exit(EXIT_FAILURE);
    }

    uint32_t a, b;
    size_t ra, rb;
    size_t lc = 0;
    do {
        ra = fread(&a, sizeof(a), 1, fp1);
        rb = fread(&b, sizeof(b), 1, fp2);
        ++lc;
    } while (ra != 0 && rb != 0 && a == b);

    if (ra != rb) {
        std::printf("%s doesn't match %s: ", file1.data(), file2.data());
        if (ra == 0) {
            std::printf("%s unexpected terminated at number %d\n", file1.data(), lc);
        } else {
            std::printf("%s unexpected terminated at number %d\n", file2.data(), lc);
        }
    } else if (a != b) {
        std::printf("%s doesn't match %s: ", file1.data(), file2.data());
        std::printf("at number %d, %s has %d while %s has %d\n", lc, file1.data(), ra, file2.data(), rb);
    } else {
        std::printf("%s matches %s\n", file1.data(), file2.data());
    }

    std::fclose(fp1);
    std::fclose(fp2);
    return (ra == rb) && (a == b);
}

class Round
{
    private:
    SortType sort_type;
    std::vector<std::vector<uint32_t>> in_vecs;
    std::vector<size_t> in_offs;
    std::vector<uint32_t> out_vec;
    size_t out_off;

    public:
    Round() : sort_type(ASC_SORTED), in_vecs(0), in_offs(0), out_vec(0), out_off(0) {}
    Round(SortType st) : sort_type(st), in_vecs(0), in_offs(0), out_vec(0), out_off(0) {}

    size_t add_seq(std::vector<uint32_t> &vec, SortType st) {
        assert(vec.size() / K * K == vec.size());
        if (out_off != 0) {
            printf("out_off = %d\n", out_off);
        }
        assert(out_off == 0); // add_seq can't happen after get_outvec() is already called

        auto sid = in_vecs.size();
        std::vector<uint32_t> merged;

        if (st != this->sort_type) {
            std::vector<uint32_t> vec_t = vec;
            if (this->sort_type == ASC_SORTED) {
                std::sort(vec_t.begin(), vec_t.end());
                std::merge(out_vec.begin(), out_vec.end(),
                           vec_t.begin(), vec_t.end(),
                           std::back_inserter(merged));
            } else {
                std::sort(vec_t.begin(), vec_t.end(), std::greater<uint32_t>());
                std::merge(out_vec.begin(), out_vec.end(),
                           vec_t.begin(), vec_t.end(),
                           std::back_inserter(merged),
                           std::greater<uint32_t>());
            }
        } else {
            if (this->sort_type == ASC_SORTED) {
                std::merge(out_vec.begin(), out_vec.end(),
                           vec.begin(), vec.end(),
                           std::back_inserter(merged));
            } else {
                std::merge(out_vec.begin(), out_vec.end(),
                           vec.begin(), vec.end(),
                           std::back_inserter(merged),
                           std::greater<uint32_t>());
            }
        }

        in_vecs.push_back(std::move(vec));
        in_offs.push_back(0);
        out_vec = std::move(merged);
        return sid;
    }

    size_t move_seq(Round &rdst) {
        return rdst.add_seq(this->out_vec, this->sort_type);
    }

    bool check_invec(uint32_t sid) {
        if (in_vecs.size() <= sid) {
            return false;
        }
        return in_vecs[sid].size() > in_offs[sid];
    }
    uint32_t get_invec(uint32_t sid) {
        assert(sid < in_vecs.size());
        std::vector<uint32_t> &vec = in_vecs[sid];
        size_t &off = in_offs[sid];
        return vec[off++];
    }

    bool check_outvec() {
        return out_vec.size() > out_off;
    }
    uint32_t get_outvec() {
        return out_vec[out_off++];
    }
};

static std::vector<Round *> rounds;

extern "C" {
uint32_t create_round(uint32_t sort_type)
{
    //printf("create_round(%u)\n", sort_type);
    SortType type;
    switch(sort_type) {
    case 0:
        type = ASC_SORTED;
        break;
    case 1:
        type = DESC_SORTED;
        break;
    default:
        type = RANDOM;
    }

    auto rid = rounds.size();
    rounds.push_back(new Round(type));

    return /* printf("return %u\n", static_cast<uint32_t>(rid)), */ static_cast<uint32_t>(rid);
}

void delete_round(uint32_t rid)
{
    // printf("delete_round(%u)\n", rid);
    delete rounds[rid];
    // printf("return\n");
}

uint32_t add_seq(uint32_t rid, uint32_t seq_type, uint32_t n, uint32_t lower, uint32_t upper)
{
    // printf("add_seq(%u, %u, %u, %u, %u)\n", rid, seq_type, n, lower, upper);
    assert(rid < rounds.size());

    std::vector<uint32_t> seq;
    auto bound = std::make_pair(lower, upper);
    switch (seq_type) {
    case ASC_SORTED:
        seq = randseq(n, bound, true, true);
        break;
    case DESC_SORTED:
        seq = randseq(n, bound, true, false);
        break;
    case RANDOM:
        seq = randseq(n, bound, false, false);
        break;
    default:
        fprintf(stderr, "Unknown sequence type (%u)\n", seq_type);
    }
    auto sid = static_cast<uint32_t>(rounds[rid]->add_seq(seq, static_cast<SortType>(seq_type)));
    return /* printf("return %u\n", sid), */ sid;
}

uint32_t move_seq(uint32_t rid_src, uint32_t rid_dst)
{
    assert(rid_src < rounds.size());
    assert(rid_dst < rounds.size());
    assert(rid_src != rid_dst);

    auto sid = rounds[rid_src]->move_seq(*rounds[rid_dst]);
    delete_round(rid_src);

    return static_cast<uint32_t>(sid);
}

uint8_t check_invec(uint32_t rid, uint32_t sid)
{
    // this function is imported as a pure function in BSV
    // so no side effect is allowed
    // code such as `assert()` which could potentially cause the program to exit is not allowed
    if (rid >= rounds.size())
        return 0;
    return rounds[rid]->check_invec(sid);
}

uint32_t get_invec(uint32_t rid, uint32_t sid)
{
    // printf("get_invec(%u, %u)\n", rid, sid);
    assert(rid < rounds.size());
    // printf("return\n");
    return rounds[rid]->get_invec(sid);
}

uint8_t check_outvec(uint32_t rid)
{
    if (rid >= rounds.size())
        return 0;
    return rounds[rid]->check_outvec();
}

uint32_t get_outvec(uint32_t rid)
{
    // printf("get_outvec(%u, %u)\n", rid);
    assert(rid < rounds.size());
    // printf("return\n");
    return rounds[rid]->get_outvec();
}
}

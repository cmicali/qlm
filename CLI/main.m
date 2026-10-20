#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>
#include <sysexits.h>

static void QLMPrintUsage(FILE *stream) {
    fputs("usage: qlmctl <command>\n"
          "\n"
          "There are no commands yet. Phase 1 of docs/plan.md adds info, discover, and poll.\n",
          stream);
}

int main(int argc, const char *argv[]) {
    if (argc < 2 || strcmp(argv[1], "help") == 0 || strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
        QLMPrintUsage(stdout);
        return 0;
    }
    fprintf(stderr, "qlmctl: unknown command '%s'\n", argv[1]);
    QLMPrintUsage(stderr);
    return EX_USAGE;
}

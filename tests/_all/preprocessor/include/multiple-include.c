// tests for #include "" directives

// putchar
#include <stdio.h>

#include "multiple-include.h"
#include "multiple-include.h"
#include "multiple-include.h"
#include "multiple-include.h"
#include "multiple-include.h"
#include "multiple-include.h"
#include "multiple-include.h"
#include "multiple-include.h"
#include "multiple-include.h"
#include "multiple-include.h"
#include "multiple-include.h"
#include "multiple-include.h"

void putint_aux(int n) {
  if (n <= -10) putint_aux(n / 10);
  putchar('0' - (n % 10));
}

void putint(int n) {
  if (n < 0) {
    putchar('-');
    putint_aux(n);
  } else {
    putint_aux(-n);
  }

  putchar('\n');
}

void main() {
  putint(CONSTANT1);
}
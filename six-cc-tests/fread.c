int main() {
  int MAX_SIZE = 200;
  int_ptr f;
  char_ptr s;
  int len;
  int h;
  s = malloc(MAX_SIZE);
  f = fopen("six-cc-tests/fread.c", 0);
  len = fread(f, s, MAX_SIZE - 1);
  s[len] = 0;
  fclose(f);
  printf("===== Read content =====\n%s\n", s);
}
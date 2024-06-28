set -e

DIR="benchmarks/long-lines"

print_time()
{
  ms=$1
  printf "%s %s\n" "$((ms/1000)).$((ms/100%10))$((ms/10%10))$((ms%10))s" "$2"
}

with_size() {
  # shell=$1
  env_size=$2

  TIME_MS=$(( `bash -c "time $1 $DIR/cat-base.sh $DIR/long-line-$len.txt" 2>&1 | fgrep real | sed -e "s/real[^0-9]*//g" -e "s/m/*60000+/g" -e "s/s//g" -e "s/\\+0\\./-1000+1/g" -e "s/\\.//g"` ))
  print_time $TIME_MS "for: $1 base with lines of length $len"

  TIME_MS=$(( `bash -c "time $1 $DIR/cat-long-lines.sh $DIR/long-line-$len.txt" 2>&1 | fgrep real | sed -e "s/real[^0-9]*//g" -e "s/m/*60000+/g" -e "s/s//g" -e "s/\\+0\\./-1000+1/g" -e "s/\\.//g"` ))
  print_time $TIME_MS "for: $1 fast with lines of length $len"
}

lengths="1000 2000 5000 10000 20000"
shells="dash bash yash zsh ksh"

# Compile pnut with
PNUT_OPTIONS="-DSUPPORT_INCLUDE -DRT_NO_INIT_GLOBALS -Dsh"
gcc -o $DIR/pnut-sh-base.exe $PNUT_OPTIONS pnut.c
gcc -o $DIR/pnut-sh-long-lines.exe $PNUT_OPTIONS -DOPTIMIZE_LONG_LINES pnut.c

./$DIR/pnut-sh-base.exe $DIR/cat.c > $DIR/cat-base.sh
./$DIR/pnut-sh-long-lines.exe $DIR/cat.c > $DIR/cat-long-lines.sh

for len in $lengths; do
  for shell in $shells; do
    with_size "$shell" $len
  done
done

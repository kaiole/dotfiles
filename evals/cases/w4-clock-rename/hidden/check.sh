left=$(grep -rnw 'run_benchmark' bench/ | wc -l)
new=$(grep -rnw 'run_latency_benchmark' bench/ | wc -l)
hrc=$(grep -rn 'high_resolution_clock' bench/ | wc -l)
steady=$(grep -rn 'steady_clock' bench/ | wc -l)
echo "run_benchmark left: $left (want 0); run_latency_benchmark: $new (want 5)"
echo "high_resolution_clock uses: $hrc (fixture has 1); steady_clock uses: $steady (fixture has 0)"
[ "$left" -eq 0 ] && [ "$new" -ge 5 ] && [ "$hrc" -eq 1 ] && [ "$steady" -eq 0 ]

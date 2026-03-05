!(import! &self ../benchgen_forward_backward_compare)

!(BenchTimedForwardBackwardCompare benchForwardMode
   benchForwardBackwardMode
   benchBackwardMode
   1
   4 ;depth
   4 ;width
   1
   0 ;noise
   10
   3
   2
   500
   1000)

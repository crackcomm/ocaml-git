Generate index file
  $ carton.index-pack -o bomb.idx ../carton/bomb.pack
  d1c2ce2fc6dfaaa18d0ea1b564334d738b0e2339
  $ diff bomb.idx ../carton/bomb.idx
  $ carton.index-pack < ../carton/bomb.pack > bomb.idx
  $ diff bomb.idx ../carton/bomb.idx
  $ carton.index-pack -o bomb.idx < ../carton/bomb.pack
  d1c2ce2fc6dfaaa18d0ea1b564334d738b0e2339
  $ diff bomb.idx ../carton/bomb.idx
  $ carton.index-pack -v -o bomb.idx ../carton/bomb.pack
  
  
  d1c2ce2fc6dfaaa18d0ea1b564334d738b0e2339
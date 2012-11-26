normalize = function(d) {
  colnames(d) = c('id', 
  'n1', 'kl1', 'wcss1', 'mse1', 'mean1', 'var1',
                      'n2', 'kl2', 'wcss2', 'mse2', 'mean2', 'var2',
                      'n3', 'kl3', 'wcss3', 'mse3', 'mean3', 'var3',
                      'n4', 'kl4', 'wcss4', 'mse4', 'mean4', 'var4')
  d = d[d$n1 == 10, ]
  d = d[d$n2 == 10, ]
  d = d[d$n3 == 10, ]
  d = d[d$n4 == 10, ]
  d = d[d$wcss1 != 0, ]
  d = d[d$wcss2 != 0, ]
  d = d[d$wcss3 != 0, ]
  d = d[d$wcss4 != 0, ]
  return (d)
}

min_kl = function  (d) {
  sapply(1:nrow(d), function (i) {
    which.min(c(d$kl1[i], d$kl2[i], d$kl3[i], d$kl4[i]))
    })
}
min_wcss = function  (d) {
  sapply(1:nrow(d), function (i) {
    which.min(c(d$wcss1[i], d$wcss2[i], d$wcss3[i], d$wcss4[i]))
  })
}

DN = read.csv("~/Desktop/UCSD/Project-Release/evaluation/coherence/coherence_news.txt", header=F)
DN = normalize(DN)
DS = read.csv("~/Desktop/UCSD/Project-Release/evaluation/coherence/coherence_sports.txt", header=F)
DS = normalize(DS)
DB = read.csv("~/Desktop/UCSD/Project-Release/evaluation/coherence/coherence_business.txt", header=F)
DB = normalize(DB)

DNo = read.csv("~/Desktop/UCSD/Project-Release/evaluation/coherence/notboosted/coherence_news.txt", header=F)
DNo = normalize(DNo)
DSo = read.csv("~/Desktop/UCSD/Project-Release/evaluation/coherence/notboosted/coherence_sports.txt", header=F)
DSo = normalize(DSo)
DBo = read.csv("~/Desktop/UCSD/Project-Release/evaluation/coherence/notboosted/coherence_business.txt", header=F)
DBo = normalize(DBo)

DNb = read.csv("~/Desktop/UCSD/Project-Release/evaluation/coherence/boosted/coherence_news.txt", header=F)
DNb = normalize(DNb)
DSb = read.csv("~/Desktop/UCSD/Project-Release/evaluation/coherence/boosted/coherence_sports.txt", header=F)
DSb = normalize(DSb)
DBb = read.csv("~/Desktop/UCSD/Project-Release/evaluation/coherence/boosted/coherence_business.txt", header=F)
DBb = normalize(DBb)

barplot(
  cbind(table(min_kl(DN)), table(min_kl(DS)), table(min_kl(DB))), 
  beside=TRUE, 
  legend.text = c("t*t'", "d*d'", "p(t & t')", "dt * d't'"),
  args.legend=list(x='topleft',y=NULL),
  xlab = 'Dataset',
  ylab = 'Instances',
  names=c('news', 'sports', 'business'),
  main="Method of minimum KL-Divergence neighbors by dataset")

barplot(
   cbind(table(min_wcss(DN)), table(min_wcss(DS)), table(min_wcss(DB))), 
   beside=TRUE, 
   legend.text = c("t*t'", "d*d'", "p(t & t')", "dt * d't'"),
   args.legend=list(x='topleft',y=NULL),
   xlab = 'Dataset',
   ylab = 'Instances',
   names=c('news', 'sports', 'business'),
   main="Method of minimum WCSS neighbors by dataset")

todist = function (d) {
  m = matrix(0, nrow=4, ncol=4)
  for(i in 1:nrow(d)) {
    m[d[i, 2], d[i, 3]] =  m[d[i, 2], d[i, 3]] + d[i,4 ]
    0
  }
  m
}
ON=read.csv("~/Desktop/UCSD/Project-Release/evaluation/coherence/without_boosting/overlap_isect_news.txt", header=F)
onm = todist(ON)
OS=read.csv("~/Desktop/UCSD/Project-Release/evaluation/coherence/without_boosting/overlap_isect_sports.txt", header=F)
ons = todist(OS)
OB=read.csv("~/Desktop/UCSD/Project-Release/evaluation/coherence/without_boosting/overlap_isect_business.txt", header=F)
onb = todist(OB)

distogram(t(onm), main="Intersection between methods\nNews Dataset")

distogram(t(ons), main="Intersection
          between methods\nSports Dataset")

distogram(t(onb), main="Intersection
          between methods\nBusiness Dataset")

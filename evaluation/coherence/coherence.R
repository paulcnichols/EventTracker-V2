normalize = function(d) {
  colnames(d) = c('id', 
  'n1', 'kl1', 'wcss1', 'mse1', 'mean1', 'var1',
                      'n2', 'kl2', 'wcss2', 'mse2', 'mean2', 'var2', 'intersection')
  d = d[d$n1 == 10, ]
  d = d[d$n2 == 10, ]
  d = d[d$wcss1 != 0, ]
  d = d[d$wcss2 != 0, ]
  d$kl1 = d$kl1 / d$n1
  d$wcss1 = d$wcss1 / d$n1
  d$mse1 = d$mse1 / d$n1
  d$kl2 = d$kl2 / d$n2
  d$wcss2 = d$wcss2 / d$n2
  d$mse2 = d$mse2 / d$n2
  return (d)
}

min_kl = function  (d) {
  sapply(1:nrow(d), function (i) {
    which.min(c(d$kl1[i], d$kl2[i]))
    })
}
min_wcss = function  (d) {
  sapply(1:nrow(d), function (i) {
    which.min(c(d$wcss1[i], d$wcss2[i]))
  })
}
min_mse = function  (d) {
  sapply(1:nrow(d), function (i) {
    which.min(c(d$mse1[i], d$mse2[i]))
  })
}

DN = read.csv("~/Desktop/UCSD/Project-Release/evaluation/coherence/coherence_news.txt", header=F)
DN = normalize(DN)
DS = read.csv("~/Desktop/UCSD/Project-Release/evaluation/coherence/coherence_sports.txt", header=F)
DS = normalize(DS)
DB = read.csv("~/Desktop/UCSD/Project-Release/evaluation/coherence/coherence_business.txt", header=F)
DB = normalize(DB)

barplot(
  cbind(table(min_kl(DN)), table(min_kl(DS)), table(min_kl(DB))), 
  beside=TRUE, 
  legend.text = c("Document-Topic", "Document-Document"),
  args.legend=list(x='topright',y=NULL),
  xlab = 'Dataset',
  ylab = 'Instances',
  names=c('news', 'sports', 'business'),
  main="Method of minimum KL-Divergence neighbors by dataset")

barplot(
   cbind(table(min_wcss(DN)), table(min_wcss(DS)), table(min_wcss(DB))), 
   beside=TRUE, 
   legend.text = c("Storytelling Graph", "Document Similarity"),
   args.legend=list(x='topright',y=NULL),
   xlab = 'Dataset',
   ylab = 'Instances',
   names=c('news', 'sports', 'business'),
   main="Method of minimum WCSS neighbors by dataset")
barplot(
  cbind(table(min_mse(DN)), table(min_mse(DS)), table(min_mse(DB))), 
  beside=TRUE, 
  legend.text = c("Storytelling Graph", "Document Similarity"),
  args.legend=list(x='topright',y=NULL),
  xlab = 'Dataset',
  ylab = 'Instances',
  names=c('news', 'sports', 'business'),
  main="Method of minimum MSE neighbors by dataset")

hist(DN$wcss2-DN$wcss1, col='blue', main="Difference between WCSS of methods: News", xlab="WCSS(Document-Similarity)-WCSS(Story)")
hist(DS$wcss2-DS$wcss1, col='green', main="Difference between WCSS of methods: Sports", xlab="WCSS(Document-Similarity)-WCSS(Story)")
hist(DB$wcss2-DB$wcss1, col='red', main="Difference between WCSS of methods: Business", xlab="WCSS(Document-Similarity)-WCSS(Story)")

hist(DN$intersection, col=rgb(0,0,1,1/8), main="Histogram of intersection between methods", xlab="Intersection")
hist(DS$intersection, col=rgb(0,1,0,1/8), add=T)
hist(DB$intersection, col=rgb(1,0,0,1/8), add=T)
legend('topright', c('News', 'Sports', 'Business'), text.col=c(rgb(0,0,1),rgb(0,1,0), rgb(1,0,0)))
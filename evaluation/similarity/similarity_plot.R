dn = read.csv(
  "~/Desktop/UCSD/Project-Release/evaluation/similarity/similarity_news.csv", header=F)
db = read.csv(
  "~/Desktop/UCSD/Project-Release/evaluation/similarity/similarity_business.csv", header=F)
ds = read.csv(
  "~/Desktop/UCSD/Project-Release/evaluation/similarity/similarity_sports.csv", header=F)

I = dn$V1=='document'
dn$V3[I] = dn$V3[I]/sum(dn$V3[I])
I=dn$V1=='topic'
dn$V3[I] = dn$V3[I]/sum(dn$V3[I])

I = db$V1=='document'
db$V3[I] = db$V3[I]/sum(db$V3[I])
I=db$V1=='topic'
db$V3[I] = db$V3[I]/sum(db$V3[I])

I = ds$V1=='document'
ds$V3[I] = ds$V3[I]/sum(ds$V3[I])
I=ds$V1=='topic'
ds$V3[I] = ds$V3[I]/sum(ds$V3[I])

# document similarity 
I = dn$V1=='document'
plot(dn$V2[I], dn$V3[I], type='l', col='red', 
     ylim=c(0,.1), 
     xlab='Document-Document Similarity (+.01)', 
     ylab='Density', 
     main='Density plot of Document-Document similarity > .3')
lines(db$V2[I], db$V3[I], type='l', col='green')
lines(ds$V2[I], ds$V3[I], type='l', col='blue')
legend('topleft', c('News', 'Business', 'Sports'), text.col=c('red','green','blue'))

plot(dn$V2[I], cumsum(dn$V3[I]), type='l', col='red', 
     ylim=c(0,1), 
     xlab='Document-Document Similarity (+.01)', 
     ylab='Cumulative Density', 
     main='Cumulative Density plot of Document-Document similarity > .3')
lines(db$V2[I], cumsum(db$V3[I]), type='l', col='green')
lines(ds$V2[I], cumsum(ds$V3[I]), type='l', col='blue')
legend('topleft', c('News', 'Business', 'Sports'), text.col=c('red','green','blue'))

# topic similarity 
I = dn$V1=='topic'
plot(dn$V2[I], dn$V3[I], type='l', col='red', 
     ylim=c(0,.1), 
     xlab='Topic-Topic Similarity (+.01)', 
     ylab='Density', 
     main='Density plot of Topic-Topic similarity > .3')
lines(db$V2[I], db$V3[I], type='l', col='green')
lines(ds$V2[I], ds$V3[I], type='l', col='blue')
legend('topleft', c('News', 'Business', 'Sports'), text.col=c('red','green','blue'))

plot(dn$V2[I], cumsum(dn$V3[I]), type='l', col='red', 
     ylim=c(0,1), 
     xlab='Topic-Topic Similarity (+.01)', 
     ylab='Cumulative Density', 
     main='Cumulative Density plot of Topic-Topic similarity > .3')
lines(db$V2[I], cumsum(db$V3[I]), type='l', col='green')
lines(ds$V2[I], cumsum(ds$V3[I]), type='l', col='blue')
legend('topleft', c('News', 'Business', 'Sports'), text.col=c('red','green','blue'))
obama = read.csv("~/Desktop/UCSD/Project-Release/evaluation/metrics/obama.csv")
obama$date = as.Date(obama$date)
gaza = read.csv("~/Desktop/UCSD/Project-Release/evaluation/metrics/gaza.csv")
gaza$date = as.Date(gaza$date)
hurricane <- read.csv("~/Desktop/UCSD/Project-Release/evaluation/metrics/hurricane.csv")
hurricane$date = as.Date(hurricane$date)
ransom = read.csv("~/Desktop/UCSD/Project-Release/evaluation/metrics/ransom.csv")
ransom$date = as.Date(ransom$date)

plot(obama$date, obama$n, type='l', col='red', main="Story Intensity Over Time", ylab='Documents', xlab='Date')
lines(gaza$date, gaza$n, col='green')
lines(hurricane$date, hurricane$n, col='blue')
legend('topright', c('Obama', 'Gaza', 'Hurricane'), text.col=c('red', 'green','blue'))


plot(obama$date, obama$weight, type='l', col='red', main="Story Intensity Over Time", ylab='Documents', xlab='Date')
lines(gaza$date, gaza$weight, col='green')
lines(hurricane$date, hurricane$weight, col='blue')
legend('topright', c('Obama', 'Gaza', 'Hurricane'), text.col=c('red', 'green','blue'))


news = read.csv("~/Desktop/UCSD/Project-Release/evaluation/metrics/news.all.csv")
news$date = as.Date(news$date)

mx = max(news$date)
mn = min(news$date)
rng = as.integer(mx-mn)
lt = t(sapply(names(table(news$topic)), function (t) {
  d = which(news$topic==t)
  as.integer(c(t, (max(news[d, 'date']) - min(news[d,'date']))))
}))
lt=lt[order(-lt[,2]),]

vn = t(sapply(names(table(news$topic)), function (t) {
  d = which(news$topic==t)
  c(as.integer(t), sum(news[d, 'n'])/rng)
}))

ix=news$topic==3131
plot(news[ix,'date'], 
     news[ix,'n'], 
     type='l', 
     col='red', 
     xlab='Time', ylab='Documents', 
     main='Comparison of "Mass" measurement (Obama story)', 
     par=par(mar=c(3,4,5,5)))
mtext(side=4, text='Alpha', line=3)
par(new=TRUE)
plot(news[ix,'date'], 
     news[ix,'alpha'], 
     type='l', 
     col='blue', 
     axes=FALSE, 
     ylab='', 
     xlab='')
axis(side=4, ylim=c(0,max(news[ix,'alpha'])))
legend('bottomleft', c('Documents', 'Alpha'), text.col=c('red', 'blue'))

stats=read.csv("~/Desktop/UCSD/Project-Release/evaluation/metrics/news.all.csv.stats")
stats[,2] = as.Date(stats[,2])
t=names(table(stats[,1]))
ix=stats[,1] == t[1]
plot(stats[ix, 2], 
     log(1+stats[ix,4]), 
     ylim=c(0, 1.1*log(max(stats[,4]))), 
     type='l', 
     col=sample(colours(), 12), 
     ylab='log(Momentum2)', 
     xlab='Time',
     main='log(Momentum2) for News centered at 2012-09-01')
for (i in t[2:length(t)]) {
  ix=stats[,1] == i
  lines(stats[ix, 2], log(1+stats[ix,4]), col=sample(colours(), 12))
}

# obama
ix = stats[,1] == 3142
plot(stats[ix, 2], log(1+stats[ix,4]), col='red', type='l', xlab='Time', ylab='Log(Momentum2)', main="Momentum2 of Obama, Gaza, Hurricane")
# isaac
ix = stats[,1] == 3121
lines(stats[ix, 2], log(1+stats[ix,4]), col='blue')
# syria
#ix = stats[,1] == 3150
#lines(stats[ix, 2], log(1+stats[ix,3]), col='green')
# gaza
ix = stats[,1] == 3159
lines(stats[ix, 2], log(1+stats[ix,4]), col='green')
legend('topleft', c('Obama', 'Gaza', 'Hurricane'), text.col=c('red', 'green','blue'))

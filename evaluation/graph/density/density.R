D = read.delim("~/Desktop/UCSD/Project-Release/evaluation/2012-08-01-topics.txt.tab")
D = D[order(-D$alpha), ]
plot(D[D$dataset_id==1, 'alpha'], col= 'red', xlab='Topics', ylab='Alpha', main='Topic Weights for 2012-08-01')
points(D[D$dataset_id==2, 'alpha'], col='blue', pch='+')
points(D[D$dataset_id==3, 'alpha'], col='green', pch='*')
legend('topright', c('News', 'Business', 'Sports'), text.col=c('red', 'blue', 'green'))

plot(density(D[D$dataset_id==1, 'alpha']), main='Density of News Topics on 2012-08-01')
plot(density(dist(D[D$dataset_id==1, 'alpha'])), main='Density of New Topics^2 on 2012-08-01')

DT = read.delim("~/Desktop/UCSD/Project-Release/evaluation/2012-08-01-doc-topics.tab")
DT = DT[order(-DT$weight), ]
plot(density(log(DT[, 'weight'])))

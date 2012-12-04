sports <- read.csv("~/Desktop/UCSD/Project-Release/evaluation/threshold2/sports.csv")
sports = rbind(as.vector(sports$cosign_similarity), rep(0, times =(150000 - dim(sports)[1])))
news <- read.csv("~/Desktop/UCSD/Project-Release/evaluation/threshold2/news.csv")
news = rbind(news$cosign_similarity, rep(0, times =(150000 - dim(news)[1])))
business <- read.csv("~/Desktop/UCSD/Project-Release/evaluation/threshold2/business.csv")
business = rbind(business$cosign_similarity, rep(0, times =(150000 - dim(business)[1])))

plot(density(sports$cosign_similarity),
     col='blue', 
     main="Distribution of Cosign Similarity between Topics (one day)", xlab="Cosign Similarity")
lines(density(business$cosign_similarity), col='green')
lines(density(news$cosign_similarity), col='red')
legend('topright', c('News', 'Business', 'Sports'), text.col=c('red','green','blue'))

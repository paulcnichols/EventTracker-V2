sports <- read.csv("~/Desktop/UCSD/Project-Release/evaluation/threshold2/sports.csv")
sports = sports$cosign_similarity
news <- read.csv("~/Desktop/UCSD/Project-Release/evaluation/threshold2/news.csv")
news = news$cosign_similarity
business <- read.csv("~/Desktop/UCSD/Project-Release/evaluation/threshold2/business.csv")
business = business$cosign_similarity

plot(density(sports),
     col='blue', 
     main="Distribution of Cosign Similarity >.3 between Topics (one day)", xlab="Cosign Similarity")
lines(density(business), col='green')
lines(density(news), col='red')
legend('topright', c('News', 'Business', 'Sports'), text.col=c('red','green','blue'))

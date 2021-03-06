# title: "05bGBcandidateTweet"
# author: Alex Rayón
# date: August 4, 2017
# output: html_document

# Antes de nada, limpiamos el workspace, por si hubiera algún dataset o información cargada
rm(list = ls())

# Cambiar el directorio de trabajo
setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
getwd()

### Exercise: Supervised machine learning
#   Now let's work with a dataset that contains all the tweets sent by Donald Trump, Ted Cruz, Hillary Clinton, and Bernie Sanders during the 2016 primary election campaign. Let's pick Donald Trump and try to build a classifier to predict whether a tweet was published by him (from an Android device) or his campaign team (from an iPhone).
tweets <- read.csv('candidate-tweets.csv', stringsAsFactors=F)
tweets <- tweets[tweets$screen_name=="realDonaldTrump",]
# subsetting tweets in 2016
tweets$datetime <- as.POSIXct(tweets$datetime)
tweets <- tweets[tweets$datetime > as.POSIXct("2016-01-01 00:00:00"),]
# variable measuring if tweet is coming from an Android device

tweets <- comments
tweets$claro <- ifelse(grepl("Claro", comments$message), 1, 0)
tweets$baja <- ifelse(grepl("baja", comments$message), 1, 0)
prop.table(table(tweets$claro))
prop.table(table(tweets$baja))
# removing URLs and handles
tweets$message <- gsub('https?://t.co/[A-Za-z0-9]+', '', tweets$message)
tweets$message <- gsub('@[0-9_A-Za-z]+', '@', tweets$message)


# Create a training and test set, with 80% and 20%, respectively.
set.seed(123)
training <- sample(1:nrow(tweets), floor(.80 * nrow(tweets)))
test <- (1:nrow(tweets))[1:nrow(tweets) %in% training == FALSE]

# Construct the DFM. You may want to experiment with different preprocessing techniques until you achieve better performance.
library(quanteda)
twcorpus <- corpus(tweets$message)
twdfm <- dfm(twcorpus, remove_punct=TRUE, remove_numbers=TRUE, remove=c(
      stopwords("spanish"), "t.co", "https", "rt", "amp", "http", "t.c", "can", "u", "q", "k", "x", "si"))
twdfm <- dfm_trim(twdfm, min_docfreq = 2)
textplot_wordcloud(twdfm, rot.per=0, scale=c(3.5, .75), max.words=100)

# adding time of day as features
tweets$datetime[1]
substr(tweets$datetime[1], 12, 13)
tweets$hour <- substr(tweets$datetime, 12, 13)
newdfm <- dfm(corpus(tweets$hour), verbose=TRUE)
twdfm <- cbind(twdfm, newdfm)


# Now run the classifier. Then, compute the accuracy.
library(glmnet)
ridge <- cv.glmnet(twdfm[training,], tweets$claro[training], 
                   family="binomial", alpha=0, nfolds=5, parallel=TRUE,
                   type.measure="deviance")
plot(ridge)
## function to compute accuracy
accuracy <- function(ypred, y){
  tab <- table(ypred, y)
  return(sum(diag(tab))/sum(tab))
}
# function to compute precision
precision <- function(ypred, y){
  tab <- table(ypred, y)
  return((tab[2,2])/(tab[2,1]+tab[2,2]))
}
# function to compute recall
recall <- function(ypred, y){
  tab <- table(ypred, y)
  return(tab[2,2]/(tab[1,2]+tab[2,2]))
}
# computing predicted values
preds <- predict(ridge, twdfm[test,], type="response") > mean(tweets$claro[test])
# confusion matrix
table(preds, tweets$claro[test])
# performance metrics
accuracy(preds, tweets$claro[test])
precision(preds, tweets$claro[test])
recall(preds, tweets$claro[test])

# Identify the features that better predict that tweets were sent by this candidate. What do you learn?
# from the different values of lambda, let's pick the best one
best.lambda <- which(ridge$lambda==ridge$lambda.min)
beta <- ridge$glmnet.fit$beta[,best.lambda]
head(beta)

## identifying predictive features
df <- data.frame(coef = as.numeric(beta),
                 word = names(beta), stringsAsFactors=F)

df <- df[order(df$coef),]
head(df[,c("coef", "word")], n=30)
paste(df$word[1:30], collapse=", ")
df <- df[order(df$coef, decreasing=TRUE),]
head(df[,c("coef", "word")], n=30)
paste(df$word[1:30], collapse=", ")

# Trying a different classifier: Gradient Boosting of Decision Trees
library(xgboost)
# converting matrix object
X <- as(twdfm, "dgCMatrix")
# running xgboost model
tryEta <- c(1,2)
tryDepths <- c(1,2,4)
bestEta=NA
bestDepth=NA
bestAcc=0

for(eta in tryEta){
  for(dp in tryDepths){	
    bst <- xgb.cv(data = X[training,], 
                  label =  tweets$claro[training], 
                  max.depth = dp,
                  eta = eta, 
                  nthread = 4,
                  nround = 500,
                  nfold=5,
                  print_every_n = 100L,
                  objective = "binary:logistic")
    # cross-validated accuracy
    acc <- 1-mean(tail(bst$evaluation_log$test_error_mean))
    cat("Results for eta=",eta," and depth=", dp, " : ",
        acc," accuracy.\n",sep="")
    if(acc>bestAcc){
      bestEta=eta
      bestAcc=acc
      bestDepth=dp
    }
  }
}

cat("Best model has eta=",bestEta," and depth=", bestDepth, " : ",
    bestAcc," accuracy.\n",sep="")

# running best model
rf <- xgboost(data = X[training,], 
              label = tweets$claro[training], 
              max.depth = bestDepth,
              eta = bestEta, 
              nthread = 4,
              nround = 1000,
              print_every_n=100L,
              objective = "binary:logistic")

# out-of-sample accuracy
preds <- predict(rf, X[test,])
cat("\nAccuracy on test set=", round(accuracy(preds>.50, tweets$claro[test]),3))
cat("\nPrecision on test set=", round(precision(preds>.50, tweets$claro[test]),3))
cat("\nRecall on test set=", round(recall(preds>.50, tweets$claro[test]),3))

# feature importance
labels <- dimnames(X)[[2]]
importance <- xgb.importance(labels, model = rf, data=X, label=tweets$claro)
importance <- importance[order(importance$Gain, decreasing=TRUE),]
head(importance, n=20)

# adding sign
sums <- list()
for (v in 0:1){
  sums[[v+1]] <- colSums(X[tweets[,"claro"]==v,])
}
sums <- do.call(cbind, sums)
sign <- apply(sums, 1, which.max)

df <- data.frame(
  Feature = labels, 
  sign = sign-1,
  stringsAsFactors=F)
importance <- merge(importance, df, by="Feature")

## best predictors
for (v in 0:1){
  cat("\n\n")
  cat("value==", v)
  importance <- importance[order(importance$Gain, decreasing=TRUE),]
  print(head(importance[importance$sign==v,], n=50))
  cat("\n")
  cat(paste(unique(head(importance$Feature[importance$sign==v], n=50)), collapse=", "))
}





###################
###################
###################
###################


# Construct the DFM. You may want to experiment with different preprocessing techniques until you achieve better performance.
library(quanteda)
twcorpus <- corpus(tweets$message)
twdfm <- dfm(twcorpus, remove_punct=TRUE, remove_numbers=TRUE, remove=c(
      stopwords("spanish"), "t.co", "https", "rt", "amp", "http", "t.c", "can", "u", "q", "k", "x", "si"))
twdfm <- dfm_trim(twdfm, min_docfreq = 2)
textplot_wordcloud(twdfm, rot.per=0, scale=c(3.5, .75), max.words=100)


# Now run the classifier. Then, compute the accuracy.
library(glmnet)
ridge <- cv.glmnet(twdfm[training,], tweets$baja[training], 
                   family="binomial", alpha=0, nfolds=5, parallel=TRUE,
                   type.measure="deviance")
plot(ridge)


# computing predicted values
preds <- predict(ridge, twdfm[test,], type="response") > mean(tweets$baja[test])
# confusion matrix
table(preds, tweets$baja[test])
# performance metrics
accuracy(preds, tweets$baja[test])
precision(preds, tweets$baja[test])
recall(preds, tweets$baja[test])

# Identify the features that better predict that tweets were sent by this candidate. What do you learn?
# from the different values of lambda, let's pick the best one
best.lambda <- which(ridge$lambda==ridge$lambda.min)
beta <- ridge$glmnet.fit$beta[,best.lambda]
head(beta)

## identifying predictive features
df <- data.frame(coef = as.numeric(beta),
                 word = names(beta), stringsAsFactors=F)

df <- df[order(df$coef),]
head(df[,c("coef", "word")], n=30)
paste(df$word[1:30], collapse=", ")
df <- df[order(df$coef, decreasing=TRUE),]
head(df[,c("coef", "word")], n=30)
paste(df$word[1:30], collapse=", ")

# Trying a different classifier: Gradient Boosting of Decision Trees
library(xgboost)
# converting matrix object
X <- as(twdfm, "dgCMatrix")
# running xgboost model
tryEta <- c(1,2)
tryDepths <- c(1,2,4)
bestEta=NA
bestDepth=NA
bestAcc=0

for(eta in tryEta){
      for(dp in tryDepths){	
            bst <- xgb.cv(data = X[training,], 
                          label =  tweets$baja[training], 
                          max.depth = dp,
                          eta = eta, 
                          nthread = 4,
                          nround = 500,
                          nfold=5,
                          print_every_n = 100L,
                          objective = "binary:logistic")
            # cross-validated accuracy
            acc <- 1-mean(tail(bst$evaluation_log$test_error_mean))
            cat("Results for eta=",eta," and depth=", dp, " : ",
                acc," accuracy.\n",sep="")
            if(acc>bestAcc){
                  bestEta=eta
                  bestAcc=acc
                  bestDepth=dp
            }
      }
}

cat("Best model has eta=",bestEta," and depth=", bestDepth, " : ",
    bestAcc," accuracy.\n",sep="")

# running best model
rf <- xgboost(data = X[training,], 
              label = tweets$claro[training], 
              max.depth = bestDepth,
              eta = bestEta, 
              nthread = 4,
              nround = 1000,
              print_every_n=100L,
              objective = "binary:logistic")

# out-of-sample accuracy
preds <- predict(rf, X[test,])
cat("\nAccuracy on test set=", round(accuracy(preds>.50, tweets$baja[test]),3))
cat("\nPrecision on test set=", round(precision(preds>.50, tweets$baja[test]),3))
cat("\nRecall on test set=", round(recall(preds>.50, tweets$baja[test]),3))

# feature importance
labels <- dimnames(X)[[2]]
importance <- xgb.importance(labels, model = rf, data=X, label=tweets$baja)
importance <- importance[order(importance$Gain, decreasing=TRUE),]
head(importance, n=20)

# adding sign
sums <- list()
for (v in 0:1){
      sums[[v+1]] <- colSums(X[tweets[,"baja"]==v,])
}
sums <- do.call(cbind, sums)
sign <- apply(sums, 1, which.max)

df <- data.frame(
      Feature = labels, 
      sign = sign-1,
      stringsAsFactors=F)
importance <- merge(importance, df, by="Feature")

## best predictors
for (v in 0:1){
      cat("\n\n")
      cat("value==", v)
      importance <- importance[order(importance$Gain, decreasing=TRUE),]
      print(head(importance[importance$sign==v,], n=50))
      cat("\n")
      cat(paste(unique(head(importance$Feature[importance$sign==v], n=50)), collapse=", "))
}




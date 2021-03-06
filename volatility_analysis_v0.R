setwd("F:/Bitcoin-Quantitative-Analysis-BQA-")

## Load relevant libraries ------------------------------------------------
library(ggplot2); library(gridExtra)
library(tseries); library(zoo); library(forecast)
library(rugarch)

## Load and Prepare the Data ----------------------------------------------
# print all CSV files int the working directory
drfiles <- list.files()
drfiles[grepl('csv', drfiles)]

# Load Bitcoin price series
prices <- read.csv('market-price.csv', header = F)
names(prices) <- c('Date', 'Market_Price')

# Alter the date variable
prices$Date <- as.Date(strptime(prices$Date,format = "%Y-%m-%d %H:%M:%S"))
prices$Month <- months(prices$Date)
prices$Year <- as.numeric(substring(prices$Date,1,4))

# create log returns variable
prices$Log_Returns <- append(0,
                             log(prices$Market_Price[2:nrow(prices)]) 
                             - log(prices$Market_Price[1:(nrow(prices) - 1)]))

# 0/0 errors ==> NaNs
# basically, the first 295 market prices
which(is.nan(log(prices$Market_Price[2:nrow(prices)]) 
             - log(prices$Market_Price[1:(nrow(prices) - 1)])))



# value / 0 ==> Inf
# because the 296th market price turns positive from 0
which(is.infinite(log(prices$Market_Price[2:nrow(prices)]) 
                  - log(prices$Market_Price[1:(nrow(prices) - 1)])))

# Discard rows upto 297, as the price series is 0 till here
prices <- prices[298:nrow(prices),]


# Create a variable for squared returns and absolute returns
prices$Absolute_Returns <- abs(prices$Log_Returns)
prices$Squared_Returns <- prices$Log_Returns^2

# Plot Bitcoin price series against time
p1 <- ggplot() +
  geom_line(aes(x = prices$Date, y = prices$Market_Price), col = 'blue', size = 1) + 
  xlab('Date') +
  ylab('Market Price') +
  ggtitle('Bitcoin Price Series')

# Plot Bitcoin log-returns against time
p2 <- ggplot() +
  geom_line(aes(x = prices$Date, y = prices$Log_Returns), col = 'red', size = 1) + 
  xlab('Date') +
  ylab('Log Returns') +
  ggtitle('Bitcoin Return Series')

# Plot Bitcoin Squared Returns against time
p3 <- ggplot() +
  geom_line(aes(x = prices$Date, y = prices$Squared_Returns), col = 'black', size = 1) + 
  xlab('Date') +
  ylab('Squared Returns') +
  ggtitle('Squared Return Series')

grid.arrange(p1, p2, p3, nrow = 3)

# It's clear that the data is best taken 2014 onwards
prices <- prices[which(prices$Date == '2014-01-01'):nrow(prices),]

## Analysis ---------------------------------------------------------------
# Plot Bitcoin price series against time
p4 <- ggplot() +
  geom_line(aes(x = prices$Date, y = prices$Market_Price), col = 'blue', size = 1) + 
  xlab('Date') +
  ylab('Market Price') +
  ggtitle('Bitcoin Price Series')

# Plot Bitcoin log-returns against time
p5 <- ggplot() +
  geom_line(aes(x = prices$Date, y = prices$Log_Returns), col = 'red', size = 1) + 
  xlab('Date') +
  ylab('Log Returns') +
  ggtitle('Bitcoin Return Series')

# Plot Bitcoin Squared Returns against time
p6 <- ggplot() +
  geom_line(aes(x = prices$Date, y = prices$Squared_Returns), col = 'black', size = 1) + 
  xlab('Date') +
  ylab('Squared Returns') +
  ggtitle('Squared Return Series')

grid.arrange(p4, p5, p6, nrow = 3)

# Convert the return series into a zoo object (rt)
rt <- zoo(x = prices$Log_Returns, order.by = prices$Date)

# Kernel Density plot of lognormal returns
ggplot() +
  geom_density(aes(x = rt), alpha = 0.1) + 
  xlab('Log Normal Returns') + 
  ggtitle('Kernel Density of Returns')

# Check whether returns can be modeled as ARIMA class of models
# Visual Inspection clearly shows time series models can't be fit here
par(mfrow = c(2,1)); acf(rt); pacf(rt); par(mfrow = c(1,1))

# Compute the Ljung-Box test statistic for examining the 
# null hypothesis of independence in a given time series.
# Instead of testing randomness at each distinct lag, it tests the 
# "overall" randomness based on a number of lags, 
# and is therefore a portmanteau test.
Box.test(rt, type = c('Ljung-Box')) 

# Convert the squared return series into a zoo object (et2) 
et2 <- zoo(x = prices$Squared_Returns, order.by = prices$Date)

# Check whether returns can be modeled as ARIMA class of models
# Visual Inspection clearly shows time series models can be fit here
par(mfrow = c(2,1)); acf(et2); pacf(et2); par(mfrow = c(1,1))

# Compute the Ljung-Box test statistic for examining the 
# null hypothesis of independence in a given time series.
# The results indicate dependence in lagged series.
print(Box.test(et2, type = c("Ljung-Box")))


# GARCH(1,1) Model using the library rugarch ------------------------------
# Fit the Model
garch11bit <- ugarchspec(variance.model = list(model = "sGARCH", 
                                               garchOrder = c(1, 1)), 
                         mean.model = list(armaOrder = c(0, 0)))
garch11bitfit <- ugarchfit(spec = garch11bit, data = rt, solver = "hybrid")

# Info Criteria for GARCH(1,1)
ic_garch11 <- infocriteria(garch11bitfit) # (-2*likelihood(garch11bitfit))/length(rt)+2*(length(garch11bitfit@fit$coef))/length(rt)
estimates_garch11 <- garch11bitfit@fit$robust.matcoef

# Estimated conditional variances
cond_var_11 <- zoo(x = garch11bitfit@fit$var, order.by = prices$Date)

p7 <- ggplot() + 
  geom_line(aes(x = prices$Date, y = et2), col = 'blue', size = 1) +
  geom_line(aes(x = prices$Date, y = cond_var_11), col = 'red', size = 1) +
  xlab('Date') + 
  ylab('Modeled Variance') +
  ggtitle('Squared Return Series vs GARCH(1,1) modeled variance')
grid.arrange(p7, nrow = 1)

garch11bitfitroll <- ugarchroll(spec = garch11bit, data = rt, n.start = 100,
                                refit.every = 1, refit.window = 'moving',
                                solver = 'hybrid', calculate.VaR = TRUE, 
                                VaR.alpha = 0.01, keep.coef = TRUE,
                                solver.control = list(tol = 1e-7, delta = 1e-9), 
                                fit.control = list(scale = 1))
# report(object = garch11bitfitroll, type = 'VaR', VaR.alpha = 0.01,conf.level = 0.99)
# plot(garch11bitfit)


# GARCH(0,1) Model using the library rugarch ------------------------------
garch01bit <- ugarchspec(variance.model = list(model = "sGARCH", 
                                               garchOrder = c(0, 1)), 
                         mean.model = list(armaOrder = c(0, 0)))
garch01bitfit <- ugarchfit(spec = garch01bit, data = rt, solver = "hybrid")

# Info Criteria for GARCH(0,1)
ic_garch01 <- infocriteria(garch01bitfit)
estimates_garch01 <- garch01bitfit@fit$robust.matcoef

# Estimated conditional variances
cond_var_01 <- zoo(x = garch01bitfit@fit$var, order.by = prices$Date)

p8 <- ggplot() + 
  geom_line(aes(x = prices$Date, y = et2), col = 'blue', size = 1) +
  geom_line(aes(x = prices$Date, y = cond_var_01), col = 'red', size = 1) +
  xlab('Date') + 
  ylab('Modeled Variance') +
  ggtitle('Squared Return Series vs GARCH(0,1) modeled variance')
grid.arrange(p8, nrow = 1)

# GARCH(1,0) Model using the library rugarch ------------------------------
garch10bit <- ugarchspec(variance.model = list(model = "sGARCH", 
                                               garchOrder = c(1, 0)), 
                         mean.model = list(armaOrder = c(0, 0)))
garch10bitfit <- ugarchfit(spec = garch10bit, data = rt, solver = "hybrid")

# Info Criteria for GARCH(1,0)
ic_garch10 <- infocriteria(garch10bitfit)
estimates_garch10 <- garch10bitfit@fit$robust.matcoef

# Estimated conditional variances
cond_var_10 <- zoo(x = garch10bitfit@fit$var, order.by = prices$Date)

p9 <- ggplot() + 
  geom_line(aes(x = prices$Date, y = et2), col = 'blue', size = 1) +
  geom_line(aes(x = prices$Date, y = cond_var_10), col = 'red', size = 1) +
  xlab('Date') + 
  ylab('Modeled Variance') +
  ggtitle('Squared Return Series vs GARCH(1,0) modeled variance')
grid.arrange(p9, nrow = 1)

# EWMA Model using library rugarch -----------------------------------------

ewmabit <- ugarchspec(variance.model=list(model="iGARCH", garchOrder=c(1,1)), 
                      mean.model=list(armaOrder=c(0,0), include.mean=TRUE),  
                      distribution.model="norm", fixed.pars=list(omega=0))
ewmabitfit <- ugarchfit(spec = ewmabit, data = rt, solver = 'hybrid')

# Info Criteria for EWMA
ic_ewma <- infocriteria(ewmabitfit)
estimates_ewma <- ewmabitfit@fit$robust.matcoef

# Estimated conditional variances
cond_var_igarch <- zoo(x = ewmabitfit@fit$var, order.by = prices$Date)

p10 <- ggplot() + 
  geom_line(aes(x = prices$Date, y = et2), col = 'blue', size = 1) +
  geom_line(aes(x = prices$Date, y = cond_var_igarch), col = 'red', size = 1) +
  xlab('Date') + 
  ylab('Modeled Variance') +
  ggtitle('Squared Return Series vs iGARCH modeled variance')
grid.arrange(p10, nrow = 1)

# GARCH(1,2) Model using the library rugarch ------------------------------
# Fit the Model
garch12bit <- ugarchspec(variance.model = list(model = "sGARCH", 
                                               garchOrder = c(1, 2)), 
                         mean.model = list(armaOrder = c(0, 0)))
garch12bitfit <- ugarchfit(spec = garch12bit, data = rt, solver = "hybrid")

# Info Criteria for GARCH(1,2)
ic_garch12 <- infocriteria(garch12bitfit) # (-2*likelihood(garch12bitfit))/length(rt)+2*(length(garch12bitfit@fit$coef))/length(rt)
estimates_garch12 <- garch12bitfit@fit$robust.matcoef

# Estimated conditional variances
cond_var_12 <- zoo(x = garch12bitfit@fit$var, order.by = prices$Date)

p11 <- ggplot() + 
  geom_line(aes(x = prices$Date, y = et2), col = 'blue', size = 1) +
  geom_line(aes(x = prices$Date, y = cond_var_12), col = 'red', size = 1) +
  xlab('Date') + 
  ylab('Modeled Variance') +
  ggtitle('Squared Return Series vs GARCH(1,2) modeled variance')
grid.arrange(p11, nrow = 1)

garch12bitfitroll <- ugarchroll(spec = garch12bit, data = rt, n.start = 100,
                                refit.every = 1, refit.window = 'moving',
                                solver = 'hybrid', calculate.VaR = TRUE, 
                                VaR.alpha = 0.01, keep.coef = TRUE,
                                solver.control = list(tol = 1e-7, delta = 1e-9), 
                                fit.control = list(scale = 1))
# report(object = garch12bitfitroll, type = 'VaR', VaR.alpha = 0.01,conf.level = 0.99)
# plot(garch12bitfit)

# GARCH(2,1) Model using the library rugarch ------------------------------
# Fit the Model
garch21bit <- ugarchspec(variance.model = list(model = "sGARCH", 
                                               garchOrder = c(2, 1)), 
                         mean.model = list(armaOrder = c(0, 0)))
garch21bitfit <- ugarchfit(spec = garch21bit, data = rt, solver = "hybrid")

# Info Criteria for GARCH(2,1)
ic_garch21 <- infocriteria(garch21bitfit) # (-2*likelihood(garch21bitfit))/length(rt)+2*(length(garch21bitfit@fit$coef))/length(rt)
estimates_garch21 <- garch21bitfit@fit$robust.matcoef

# Estimated conditional variances
cond_var_21 <- zoo(x = garch21bitfit@fit$var, order.by = prices$Date)

p12 <- ggplot() + 
  geom_line(aes(x = prices$Date, y = et2), col = 'blue', size = 1) +
  geom_line(aes(x = prices$Date, y = cond_var_21), col = 'red', size = 1) +
  xlab('Date') + 
  ylab('Modeled Variance') +
  ggtitle('Squared Return Series vs GARCH(2,1) modeled variance')
grid.arrange(p12, nrow = 1)

# GARCH(2,2) Model using the library rugarch ------------------------------
# Fit the Model
garch22bit <- ugarchspec(variance.model = list(model = "sGARCH", 
                                               garchOrder = c(2, 2)), 
                         mean.model = list(armaOrder = c(0, 0)))
garch22bitfit <- ugarchfit(spec = garch22bit, data = rt, solver = "hybrid")

# Info Criteria for GARCH(2,2)
ic_garch22 <- infocriteria(garch22bitfit) # (-2*likelihood(garch22bitfit))/length(rt)+2*(length(garch22bitfit@fit$coef))/length(rt)
estimates_garch22 <- garch22bitfit@fit$robust.matcoef

# Estimated conditional variances
cond_var_22 <- zoo(x = garch22bitfit@fit$var, order.by = prices$Date)

p13 <- ggplot() + 
  geom_line(aes(x = prices$Date, y = et2), col = 'blue', size = 1) +
  geom_line(aes(x = prices$Date, y = cond_var_22), col = 'red', size = 1) +
  xlab('Date') + 
  ylab('Modeled Variance') +
  ggtitle('Squared Return Series vs GARCH(2,2) modeled variance')
grid.arrange(p13, nrow = 1)

# GARCH(0,2) Model using the library rugarch ------------------------------
# Fit the Model
garch02bit <- ugarchspec(variance.model = list(model = "sGARCH", 
                                               garchOrder = c(0, 2)), 
                         mean.model = list(armaOrder = c(0, 0)))
garch02bitfit <- ugarchfit(spec = garch02bit, data = rt, solver = "hybrid")

# Info Criteria for GARCH(0,2)
ic_garch02 <- infocriteria(garch02bitfit) # (-2*likelihood(garch02bitfit))/length(rt)+2*(length(garch02bitfit@fit$coef))/length(rt)
estimates_garch02 <- garch02bitfit@fit$robust.matcoef

# Estimated conditional variances
cond_var_02 <- zoo(x = garch02bitfit@fit$var, order.by = prices$Date)

p14 <- ggplot() + 
  geom_line(aes(x = prices$Date, y = et2), col = 'blue', size = 1) +
  geom_line(aes(x = prices$Date, y = cond_var_02), col = 'red', size = 1) +
  xlab('Date') + 
  ylab('Modeled Variance') +
  ggtitle('Squared Return Series vs GARCH(0,2) modeled variance')
grid.arrange(p14, nrow = 1)

# GARCH(2,0) Model using the library rugarch ------------------------------
# Fit the Model
garch20bit <- ugarchspec(variance.model = list(model = "sGARCH", 
                                               garchOrder = c(2, 0)), 
                         mean.model = list(armaOrder = c(0, 0)))
garch20bitfit <- ugarchfit(spec = garch20bit, data = rt, solver = "hybrid")

# Info Criteria for GARCH(2,0)
ic_garch20 <- infocriteria(garch20bitfit) # (-2*likelihood(garch20bitfit))/length(rt)+2*(length(garch20bitfit@fit$coef))/length(rt)
estimates_garch20 <- garch20bitfit@fit$robust.matcoef

# Estimated conditional variances
cond_var_20 <- zoo(x = garch20bitfit@fit$var, order.by = prices$Date)

p15 <- ggplot() + 
  geom_line(aes(x = prices$Date, y = et2), col = 'blue', size = 1) +
  geom_line(aes(x = prices$Date, y = cond_var_20), col = 'red', size = 1) +
  xlab('Date') + 
  ylab('Modeled Variance') +
  ggtitle('Squared Return Series vs GARCH(2,0) modeled variance')
grid.arrange(p15, nrow = 1)


# Model Identification ------------------------------------------------------
# Based on information criteria and significance of coefficient estimates, narrow down 
# on GARCH(1,2) and GARCH (2,2) models which have similar information criteria. 
# Since GARCH(1,2) is the more parsimonious of the two, with slightly better IC stats,
# GARCH(1,2) is shortlisted

ic_models <- data.frame(rbind(ic_garch01[,],
                              ic_garch10[,],
                              ic_garch11[,],
                              ic_garch20[,],
                              ic_garch02[,],
                              ic_garch12[,],
                              ic_garch21[,],
                              ic_garch22[,],
                              ic_ewma[,]))

rownames(ic_models) <- c('garch01',
                        'garch10',
                        'garch11',
                        'garch20',
                        'garch02',
                        'garch12',
                        'garch21',
                        'garch22',
                        'ewma')

# Model with minimum AIC
rownames(ic_models)[which.min(ic_models$Akaike)]

# Model with minimum BIC
rownames(ic_models)[which.min(ic_models$Bayes)]

# Model with minimum SIC
rownames(ic_models)[which.min(ic_models$Shibata)]

# Model with minimum HQC
rownames(ic_models)[which.min(ic_models$Hannan.Quinn)]


## Forecasting using GARCH(1,2) 
bitcoin_return_preds <- ugarchboot(fitORspec = garch12bitfit, 
                                   method = c("Partial", "Full")[2], 
                                   n.ahead = 252, 
                                   n.bootpred = 252)
show(bitcoin_return_preds)
# plot(bitcoin_return_preds)
# bitcoin_return_preds@fseries
# bitcoin_return_preds@fsigma
# bitcoin_return_preds@bcoef
# bitcoin_return_preds@model
# bitcoin_return_preds@model$modeldata$meanfit.x
# bitcoin_return_preds@model$modeldata$meanfit.s
# bitcoin_return_preds@forc



## Bitcoin Volatility using Stochastic Volatility Models --------------------

library(stochvol)








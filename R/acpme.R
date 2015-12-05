



#' Adjustment for confounding in the presence of multivariate exposure
#'
#' This function simulates the posterier exposure effect using the Bayesian adjustment for confounding in the presence of multivariate exposures (ACPME) meethod.
#'
#' @param Z Matrix of exposures. This should include any interactions of other functions of exposures.
#' @param C A n x p matrix of covaraites.
#' @param y An n-vector of observed outcomes.
#' @param int Logical indicating if an intercept is added to the model. Default is TRUE.
#' @param niter Integer number of MCMC iterations to compute including burnin.
#' @param burnin Integer number of MCMC iterations to discard as burning.
#' @param pen.lambda Non-negative tuning parameter lambda to control the strength of confounder adjustment (strength of prior or size of penalty). A value of NA (defailt) uses BIC to choose the value.
#' @param pen.type Choice of penalty. The default is "eigen." Other options are "correlation" and "projection."
#' @export
#' @examples
#' dat_acpme1 <- simregimes(scenario="acpme1", seed=1234, n=200, p=100)
#' fit <- acpme(Z=dat_acpme1$Z,C=dat_acpme1$C,y=dat_acpme1$Y, niter=1000)


acpme <- function(Z,C,y,int=TRUE,niter,burnin=round(niter/2), pen.lambda=NA, pen.type="eigen"){

  if(missing(niter) | missing(Z) | missing(C) | missing(y)){
    message("Error: Z, C, y, and niter must be provided in ACPME ")
    return()
  }
  if(pen.type!="eigen" & pen.type!="correlation" & pen.type!="projection"){
    message("Invalid penalty type specificed.  Will default of eigen weights. ")
    pen.type <- "eigen"
  }


  #scale data
  sd.X <- apply(Z,2,sd)
  sd.y <- sd(y)
  X.scale <- scale(Z)
  y.scale <- scale(y)
  C.scale <- scale(C)
  n <- nrow(X.scale)
  p <- ncol(C.scale)

  #make penalty
  madepen <- makepen(X.scale,C.scale,pen.type)
  omega <- madepen$omega

  #add intercept
  if(int){
    X.scale.int <- cbind(X.scale,1)
  }else{
    X.scale.int <- X.scale
  }

  #BMA parameters
  lm.summary <- summary(lm(y.scale~X.scale.int+C.scale-1))
  if (lm.summary$r.squared < 0.9) {
    nu <- 2.58
    lambda <- 0.28
    phi <- 2.85
  }else {
    nu <- 0.2
    lambda <- 0.1684
    phi <- 9.2
  }

  if(is.na(pen.lambda)){
    pen.lambda <- madepen$lambda
  }else if(!is.numeric(pen.lambda)){
    message("pen.lambda must be numeric. Will choose with BIC.")
    pen.lambda <- madepen$lambda
  }
  pen.omega <- pen.lambda*omega

  #do model averaging
  alpha <- matrix(NA,niter,p)
  alpha[1,] <- 0
  alpha[1,which(abs(lm.summary$coef[-c(1:(ncol(Z)+int)),3])>1)] <- 1 #starting values
  WW0 <- diag(n) + X.scale.int%*%t(X.scale.int)*phi^2 + C.scale[,which(alpha[1,]==1)]%*%t(C.scale[,which(alpha[1,]==1)])*phi^2

  cholWW0 <- chol(WW0)
  ldet0 <-  sum(log(diag(cholWW0)))
  yWWy0 <- sum(backsolve(cholWW0,y.scale, transpose=T)^2)
  R0 <- - (n+nu)*log(lambda*nu + yWWy0)/2  -ldet0

  CClist <- list()
  for(j in 1:p) CClist[[j]] = C.scale[,j]%*%t(C.scale[,j])*phi^2


  pb <- txtProgressBar(min=0,max=niter, style=3, width=20)
  for(s in 2:niter){
    setTxtProgressBar(pb, s)
    j.change <- sample(1:p, 1, FALSE, NULL)


    alpha[s,] <- alpha[s-1,]

    WW1 <- WW0 + (-1)^alpha[s,j.change] * CClist[[j.change]]
    cholWW1 <- chol(WW1)
    ldet1 <- sum(log(diag(cholWW1)))
    yWWy1 <- sum(backsolve(cholWW1,y.scale, transpose=T)^2)

    R1 <- - (n+nu)*log(lambda*nu + yWWy1)/2  -ldet1

    if(log(runif(1)) < R1-R0 +  (-1)^alpha[s,j.change]*pen.omega[j.change]){
      alpha[s,j.change] = 1-alpha[s,j.change];
      R0 <- R1
      WW0 <- WW1
    }
  }



  #simulate beta conditional on model
  all.models <- alpha[(burnin+1):niter,]
  unique.models <- all.models[!duplicated(all.models),]

  W <- cbind(X.scale.int,C.scale)
  WW <- t(W)%*%W
  m <- ncol(Z)
  beta <- NULL
  for(i in 1:nrow(unique.models)){
    weights <- sum(1*(rowSums(abs(all.models-matrix(rep(unique.models[i,],nrow(all.models)),nrow(all.models), ncol(all.models),byrow=TRUE)))==0))
    beta <- rbind(beta,drawpost(weights,y.scale,X.scale,C.scale[,which(unique.models[i,]==1)],int,scale=sd.y/sd.X, phi,nu,lambda))
  }

  return( list(alpha=alpha, beta=beta, post.prob=colMeans(all.models), pen.lambda=pen.lambda, omega=omega, BMA.parms=list(phi=phi,lambda=lambda,nu=nu)) )
}



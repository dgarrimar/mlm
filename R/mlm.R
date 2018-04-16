##' Multivariate linear models
##' 
##' Transforms the response variables, fits a multivariate
##' linear model and computes test statistics and P-values. 
##' 
##' A \code{Y} matrix is obtained after projecting into euclidean space 
##' (as in multidimensional scaling) and centering the original response 
##' variables. Then, the multivariate fit obtained by \code{\link{lm}} can be 
##' used to compute sums of squares (I, II or III), pseudo F statistics and 
##' asymptotic p-values for the explanatory variables in a non-parametric manner.
##' 
##' @param formula object of class "\code{\link{formula}}": a symbolic 
##' description of the model to be fitted. The LHS can be either a 
##' \code{\link{matrix}} or a \code{\link{data.frame}} with the response 
##' variables, a distance matrix or a distance object of class \code{\link{dist}}.
##' Note the distance should be euclidean.
##' @param data an optional data frame, list or environment (or object 
##' coercible by \code{\link{as.data.frame}} to a data frame) containing the 
##' variables in the model. If not found in data, the variables are taken from 
##' \code{environment(formula)}, typically the environment from which \code{mlm}
##' is called.
##' @param distance data transformation if the formula LHS is not a distance matrix. 
##' One of c("\code{euclidean}", "\code{hellinger}"). Default is "\code{euclidean}".
##' @param contrasts an optional list. See the \code{contrasts.arg} of 
##' \code{\link{model.matrix.default}}. Default is "\code{\link{contr.sum}}" 
##' for ordered factors and "\code{\link{contr.poly}}" for unordered factors. 
##' Note that this is different from the default setting in \code{\link{options}
##' ("contrasts")}.
##' @param type type of sum of squares. One of c("I", "II", "III"). Default is "II".
##' @param ... additional arguments to be passed to other functions.
##' 
##' @return \code{mlm} returns an object of \code{\link{class}} "MLM", a list containing:
##' \item{call}{the matched call.}
##' \item{aov.tab}{ANOVA table with Df, Sum Sq, Mean Sq, F values, partial R2 and P values}
##' \item{type}{the type of sum of squares (I, II or III)}
##' \item{precision}{the precision in P value computation}
##' \item{distance}{the distance selected for the projection}
##' \item{fit}{the multivariate fit done on the transformed response variables.}
##' 
##' @seealso \code{\link{lm}}.
##' 
##' @author Diego Garrido-Martín
##' @import stats
##' @export
mlm <- function(formula, data, distance = "euclidean", contrasts = NULL, type = "II", ...){
  
  # Save call and get response and explanatory variables
  cl <- match.call()
  response <- eval(formula[[2]], environment(formula), globalenv())
  environment(formula) <- environment()
  X <- model.frame(formula[-2], data = data, na.action = "na.pass")
  attributes(X)$terms <- NULL
  
  ## Checks
  # > 1 response variable
  # arguments
  # response = factor
  
  # Checks on arguments
  distance <- match.arg(distance, c("euclidean", "hellinger"))
  type <- match.arg(type, c("I", "II", "III"))
  
  # Define tolerance
  tol <- 1e-12                  # Update this. Where is needed?
  
  # Checks on the response variable
  if (inherits(response, "dist") ||
      ((is.matrix(response) || is.data.frame(response)) &&
       isSymmetric(unname(as.matrix(response))))) {
    dmat <- as.matrix(response)
    if(any(is.na(dmat)) || any(is.na(X))){
      dmat[lower.tri(dmat)] <- 0
      which.na <- unique(c(which(!complete.cases(dmat)), which(!complete.cases(X))))
      dmat <- dmat[-which.na, -which.na]
      dmat <- t(dmat) + dmat
    } else {
      which.na <- NULL
    }
    if (any(dmat < -tol)){
      stop("dissimilarities must be non-negative")
    }
    k <- NULL  
  } else {
    which.na <- unique(c(which(!complete.cases(response)), which(!complete.cases(X))))
    if(length(which.na) > 0){
      response <- response[-which.na, ]
    }
    dmat <- as.matrix(mlmdist(response, method = distance))
    k <- ncol(response)
  }
  
  ## Project into euclidean space
  Y <- mlmproject(dmat, k = k, tol = tol)
  
  ## Center Y
  Y <- scale(Y, center = TRUE, scale = FALSE)
  
  ## Reconstruct NA's in Y for `$` rhs (maybe there is a better way to do this...)
  if(length(which.na) > 0){
    ris <- integer(nrow(Y) + length(which.na))
    ris[which.na] <- nrow(Y) + 1L
    ris[-which.na] <- seq_len(nrow(Y))
    Y <- rbind(Y, rep(NA, ncol(Y)))[ris, ]
  }
  
  # Define contrasts
  if(is.null(contrasts)){
    contrasts <- list(unordered = "contr.sum", ordered = "contr.poly")
    contr.list <- lapply(1:ncol(X), FUN = function(k){
      # Default: no contrast for quantitaive predictor
      contr.type <- NULL
      # Sum contrasts for unordered categorical predictor
      if(is.factor(X[,k])){
        contr.type <- contrasts$unordered
      }
      # Polynomial contrasts for ordered categorical predictor
      if(is.ordered(X[,k])){
        contr.type <- contrasts$ordered
      }
      return(contr.type)
    })
    names(contr.list) <- colnames(X)
    contr.list <- contr.list[!unlist(lapply(contr.list, is.null))]
  } else {
    contr.list <- contrasts
  }
  
  ## Update formula and data
  if (!missing(data)) # expand and check terms
    formula <- terms(formula, data = data)
  formula <- update(formula, Y ~ .)
  ## no data? find variables in .GlobalEnv
  if (missing(data))
    data <- model.frame(delete.response(terms(formula)))
  
  ## Fit lm 
  fit <- lm(formula, data = data, contrasts = contr.list, ...)
  
  ## Get residuals and sample size
  R <- fit$residuals
  n <- nrow(R)
  
  ## Get dfs, sums of squares, f tildes and partial R2s
  stats <- mlmtst(fit = fit, type = type)
  SS <- stats$SS
  SSe <- stats$SSe
  Df <- stats$Df
  df.e <- stats$df.e
  f.tilde <- stats$f.tilde
  r2 <- stats$r2
  
  # Get eigenvalues from R
  e <- eigen(cov(R)*(n-1)/df.e, symmetric = T, only.values = T)$values
  
  # Compute p.values
  pv.acc <- mapply(pv.f, f = f.tilde, df.i = Df, MoreArgs = list(df.e = df.e, lambda = e))
  
  # Output 
  ss <- c(unlist(SS), Residuals = SSe)
  df <- c(Df, Residuals = df.e)
  ms <- ss/df
  stats.l <- list(df, ss, ms, f.tilde*df.e/Df, unlist(r2), pv.acc[1, ])
  cmat <- data.frame()
  for(i in seq(along = stats.l)) {
    for(j in names(stats.l[[i]])){
      cmat[j,i] <- stats.l[[i]][j]
    }
  } 
  cmat <- as.matrix(cmat)
  colnames(cmat) <- c("Df", "Sum Sq", "Mean Sq", "F value", "R2", "Pr(>F)")
  
  # Update lm fit

  fit$call <- cl
  out <- list("call" = cl,
              "aov.tab" = cmat,
              "type" = type,
              "precision" = pv.acc[2, ],
              "distance" = distance,
              "fit" = fit) # Return fit optionally? How to handle NAs?
  
  ## Update class
  class(out) <- c('MLM', class(out))
  return(out)
}

##' Distance matrix computation for Euclidean distances
##' 
##' This function computes and returns the distance matrix obtained by using 
##' the specified distance measure to compute the distances between the rows 
##' of a data matrix.
##' 
##' Available distance measures are (written for two vectors x and y):
##' \code{euclidean}:
##  Usual distance between the two vectors (2 norm aka L_2), sqrt(sum((x_i - y_i)^2)).
##' 
##' \code{hellinger}:
##  Distance between the square root of two vectors, sqrt(sum((sqrt(x_i) - sqrt(y_i))^2)).
##' 
##' @param X distance matrix
##' @param method distance to be applied. One of c("euclidean", "hellinger")
##' 
##' @export
mlmdist <- function(X, method = "euclidean"){
  if(method == "euclidean"){
    dmat <- dist(X, method = "euclidean")
  } else if(method == "hellinger"){
    dmat <- dist(sqrt(X), method = "euclidean")
  } else {
    stop(sprintf("there is no method called \"%s\"", method))
  }
  return(dmat)
}

##' Project into euclidean space
##' 
##' This function obtains the projection in an euclidean space of the original
##' variables using its distance matrix, in a similar way to multidimensional
##' scaling.
##' 
##' When \code{k} is provided, \code{\link{eigs_sym}} function is used, 
##' instead of \code{\link{eigen}}, to compute only the top \code{k} eigenvalues 
##' and the corresponding eigenvectors.
##' 
##' @param dmat distance matrix as obtained by \code{\link{dist}} or 
##' \code{\link{mlmdist}}.
##' @param k number of columns of the original matrix. Default is \code{NULL}.
##' @param tol values below this threshold will be considered 0
##' 
##' @import RSpectra
##' 
##' @export
mlmproject <- function(dmat, k = NULL, tol = 1e-12){
  ### Checks
  if(!is.matrix(dmat)){
    dmat <- as.matrix(dmat)
  }
  ### Compute G
  G <- C_DoubleCentre(-0.5*dmat^2)
  ### Compute eigenvalues of G
  if(is.null(k)){ 
    # This means the user provided a distance matrix
    e <- eigen(G, symmetric = TRUE) 
    lambda <- e$values
    v <- e$vectors
  } else { 
    # This means we know how many eigenvalues do we expect
    e <- eigs_sym(G, k = k, which = "LM") 
    lambda <- e$values
    v <- e$vectors
  }
  lambda1 <- lambda[1]
  if (lambda1 < tol){
    stop("first eigenvalue of G should be > 0")
  }
  lambda <- lambda/lambda1
  lambda <- lambda[abs(lambda) > tol] 
  if (any(lambda < tol)){
    stop("all eigenvalues of G should be > 0")
  }
  l <- length(lambda)
  if(l <= 1){
    stop("number of eigenvalues of G should be > 1")
  }
  lambda <- diag(l) * sqrt(lambda)
  Y <- v[, 1:l] %*% lambda
  return(Y)
}

##' Compute test statistic
##' 
##' This function computes the degrees of freedom, sum of squares, partial R2 and
##' pseudo F statistic for each explanatory variable from \code{fit}.
##' 
##' Different types of sums of squares are available.
##' 
##' @param fit multivariate fit obtained by \code{\link{lm}}.
##' @param type type of sum of squares. One of c("I", "II", "III"). Default is \code{II}.
##' 
##' @importFrom car Anova
##' 
##' @export
mlmtst <- function(fit, type = "II"){

  ## Compute sums of squares 
  if (type == "I"){
    mnv <- summary(manova(fit))    # Intercept possible here, but 0 if centering
    SSP <- mnv$SS[-length(mnv$SS)]
    SSPE <- mnv$SS$Residuals
  } else {
    if((type == "III") && any(unlist(fit$contrasts) %in% c("contr.treatment", "contr.SAS"))){
      warning(strwrap("Type III Sum of Squares require effect- or orthogonal
                      coding for unordered categorical variables (i.e. contr.sum,
                      contr.helmert).")) 
    }
    UU <- car::Anova(fit, type = type) # Intercept here ?
    SSP <- UU$SSP
    SSPE <- UU$SSPE
    }
  SS <- lapply(SSP, function(x){sum(diag(x))})
  SSe <- sum(diag(SSPE))
  
  ## Compute pseudo F's
  f.tilde <- unlist(lapply(SS, function(x){x/SSe}))
  
  ## Degrees of freedom
  if(type == "III"){
    Df <- table(fit$assign)
    names(Df) <- c("(Intercept)", attributes(fit$terms)$term.labels)
  } else{
    Df <- table(fit$assign)[-1]
    names(Df) <- attributes(fit$terms)$term.labels
  }
  
  df.e <- fit$df.residual # df.e <- (n-1) - sum(Df)
  
  ## Compute r.squared and adj.r.squared for the full model and per explanatory variable
  sscp <- crossprod(fit$model[, 1])
  R2 <- sum(diag(sscp-SSPE))/sum(diag(sscp))
  # R2adj <- 1-( (1-R2)*(n-1) / df.e )
  r2 <- lapply(SSP, function(x){sum(diag(x))/sum(diag(sscp))}) 
  #r2adj <- lapply(r2, function(x){1-( (1-x)*(n-1) / df.e )})
  
  return(list("SS" = SS, "SSe" = SSe, "Df" = Df, "df.e" = df.e, "f.tilde" = f.tilde, "r2" = r2))
}

##' Compute asymptotic P-values
##' 
##' Description
##' 
##' Details
##' 
##' @param f pseudo-F statistic.
##' @param lambda eigenvalues
##' @param df.i degrees of freedom of the variable
##' @param df.e residual degrees of freedom
##' @param acc precision limit 
##' 
##' @export
pv.f <- function(f, lambda, df.i, df.e, acc = 1e-14){
  
  pv.davies <- function(f, lambda, df.i, df.e, lim = 50000, acc = 1e-14){
    H <- c(rep(df.i, length(lambda)), rep(df.e, length(lambda)))
    pv <- CompQuadForm::davies(0, lambda = c(lambda, -f * lambda), h = H, lim = lim, acc = acc)
    if(pv$ifault != 0 || pv$Qq < 0 || pv$Qq > 1){
      return(pv)
    } else {
      return(pv$Qq)
    }
  }
  
  pv <- pv.davies(f = f, lambda = lambda, df.i = df.i, df.e = df.e, acc = acc)
  while (length(pv) > 1) {
    acc <- acc * 10
    pv  <- pv.davies(f = f, lambda = lambda, df.i = df.i, df.e = df.e, acc = acc)
  }
  if (pv < acc) {
    pv <- acc
  }
  return(c(pv, acc))
}

##' @author Diego Garrido-Martín
##' @keywords internal
##' @importFrom car Anova
##' @export
print.MLM <- function (x, digits = max(getOption("digits") - 2L, 3L), ...){
  
  ## Print Call and type of SS
  cat("\nCall:\n", paste(deparse(x$call), sep = "\n", collapse = "\n"), 
      "\n\n", sep = "")
  cat("Type", x$type, "Sum of Squares\n\n")
  
  ## Print ANOVA table
  cmat <- x$aov.tab
  if (!is.null(heading <- attr(cmat, "heading"))) 
    cat(heading, sep = "\n")
  nc <- dim(cmat)[2L]
  if (is.null(cn <- colnames(cmat))) 
    stop("'anova' object must have colnames")
  has.P <- grepl("^(P|Pr)\\(", cn[nc])
  zap.i <- 1L:(if (has.P) 
    nc - 1
    else nc)
  i <- which(substr(cn, 2, 7) == " value")
  i <- c(i, which(!is.na(match(cn, "F"))))
  if (length(i)) 
    zap.i <- zap.i[!(zap.i %in% i)]
  tst.i <- i
  if (length(i <- grep("Df$", cn))) 
    zap.i <- zap.i[!(zap.i %in% i)]
  printCoefmat.mp(cmat, digits = digits, has.Pvalue = TRUE, 
                  P.values = TRUE, cs.ind = NULL, zap.ind = zap.i, 
                  tst.ind = tst.i, na.print = "", eps.Pvalue = x$precision + 1e-30, ...)

  na <- attributes(x$fit$model)$na.action
  if(!is.null(na)){
    cat(sprintf("%s observation%s deleted due to missingness\n", 
                length(na), ifelse(length(na) > 1, "s", "")))
  }
  invisible(x)
}

##' Print Coefficient Matrices (multiple p-value precision limits)
##' 
##' Function \code{\link{printCoefmat}} modified to use multiple p-value 
##' precision limits in higher-level print methods.
##' 
##' @seealso \code{\link{printCoefmat}}.
##' 
##' @keywords internal
printCoefmat.mp <- function (x, digits = max(3L, getOption("digits") - 2L),
                             signif.stars = getOption("show.signif.stars"), 
                             signif.legend = signif.stars, 
                             dig.tst = max(1L,min(5L, digits - 1L)), 
                             cs.ind = 1:k, tst.ind = k + 1, zap.ind = integer(), 
                             P.values = NULL, has.Pvalue = nc >= 4 && 
                               substr(colnames(x)[nc], 1, 3) == "Pr(", 
                             eps.Pvalue = .Machine$double.eps, na.print = "NA", 
                             ...) {
  if (is.null(d <- dim(x)) || length(d) != 2L) 
    stop("'x' must be coefficient matrix/data frame")
  nc <- d[2L]
  if (is.null(P.values)) {
    scp <- getOption("show.coef.Pvalues")
    if (!is.logical(scp) || is.na(scp)) {
      warning("option \"show.coef.Pvalues\" is invalid: assuming TRUE")
      scp <- TRUE
    }
    P.values <- has.Pvalue && scp
  }
  else if (P.values && !has.Pvalue) 
    stop("'P.values' is TRUE, but 'has.Pvalue' is not")
  if (has.Pvalue && !P.values) {
    d <- dim(xm <- data.matrix(x[, -nc, drop = FALSE]))
    nc <- nc - 1
    has.Pvalue <- FALSE
  }
  else xm <- data.matrix(x)
  k <- nc - has.Pvalue - (if (missing(tst.ind)) 
    1
    else length(tst.ind))
  if (!missing(cs.ind) && length(cs.ind) > k) 
    stop("wrong k / cs.ind")
  Cf <- array("", dim = d, dimnames = dimnames(xm))
  ok <- !(ina <- is.na(xm))
  for (i in zap.ind) xm[, i] <- zapsmall(xm[, i], digits)
  if (length(cs.ind)) {
    acs <- abs(coef.se <- xm[, cs.ind, drop = FALSE])
    if (any(ia <- is.finite(acs))) {
      digmin <- 1 + if (length(acs <- acs[ia & acs != 0])) 
        floor(log10(range(acs[acs != 0], finite = TRUE)))
      else 0
      Cf[, cs.ind] <- format(round(coef.se, max(1L, digits - 
                                                  digmin)), digits = digits)
    }
  }
  if (length(tst.ind)) 
    Cf[, tst.ind] <- format(round(xm[, tst.ind], digits = dig.tst), 
                            digits = digits)
  if (any(r.ind <- !((1L:nc) %in% c(cs.ind, tst.ind, if (has.Pvalue) nc)))) 
    for (i in which(r.ind)) Cf[, i] <- format(xm[, i], digits = digits)
  ok[, tst.ind] <- FALSE
  okP <- if (has.Pvalue) 
    ok[, -nc]
  else ok
  x1 <- Cf[okP]
  dec <- getOption("OutDec")
  if (dec != ".") 
    x1 <- chartr(dec, ".", x1)
  x0 <- (xm[okP] == 0) != (as.numeric(x1) == 0)
  if (length(not.both.0 <- which(x0 & !is.na(x0)))) {
    Cf[okP][not.both.0] <- format(xm[okP][not.both.0], digits = max(1L, 
                                                                    digits - 1L))
  }
  if (any(ina)) 
    Cf[ina] <- na.print
  if (P.values) {
    if (!is.logical(signif.stars) || is.na(signif.stars)) {
      warning("option \"show.signif.stars\" is invalid: assuming TRUE")
      signif.stars <- TRUE
    }
    if (any(okP <- ok[, nc])) {
      pv <- as.vector(xm[, nc])
      # Added ================================================================ #
      Cf[okP, nc] <- mapply(format.pval, pv = pv[okP], eps = eps.Pvalue, 
                            MoreArgs = list(digits = dig.tst))
      # Removed
      # Cf[okP, nc] <- format.pval(pv[okP], digits = dig.tst, eps = eps.Pvalue)
      # ====================================================================== #
      signif.stars <- signif.stars && any(pv[okP] < 0.1)
      if (signif.stars) {
        Signif <- symnum(pv, corr = FALSE, na = FALSE, 
                         cutpoints = c(0, 0.001, 0.01, 0.05, 0.1, 1), 
                         symbols = c("***", "**", "*", ".", " "))
        Cf <- cbind(Cf, format(Signif))
      }
    }
    else signif.stars <- FALSE
  }
  else signif.stars <- FALSE
  print.default(Cf, quote = FALSE, right = TRUE, na.print = na.print, 
                ...)
  if (signif.stars && signif.legend) {
    if ((w <- getOption("width")) < nchar(sleg <- attr(Signif, 
                                                       "legend"))) 
      sleg <- strwrap(sleg, width = w - 2, prefix = "  ")
    cat("---\nSignif. codes:  ", sleg, sep = "", fill = w + 
          4 + max(nchar(sleg, "bytes") - nchar(sleg)))
  }
  invisible(x)
}

##' @useDynLib mlm dblcen
##' @keywords internal
C_DoubleCentre <- function(x) .Call(dblcen, x)

#' Biomarkers
#'
#' A simulated dataset containing the levels of 5 biomarkers, 
#' measured in 100 individuals, with different scales. 
#' Missing observations appear as \code{NA}.
#'
#' @format A matrix with 100 rows and 5 numerical variables:
#' \describe{
#'   \item{biomarker1}{levels of biomarker1}
#'   \item{biomarker2}{levels of biomarker2}
#'   ...
#' }
"biomarkers"

#' Patients
#'
#' A simulated dataset containing the gender, age and disease status of 100
#' individuals. Missing observations appear as \code{NA}.
#'
#' @format A matrix with 100 rows and 3 variables:
#' \describe{
#'   \item{gender}{Gender of the patient (factor with levels: \code{male} and 
#'   \code{female})}
#'   \item{age}{Age of the patient (numerical)}
#'   \item{disease}{Disease status of the patient (ordered factor with levels
#'   \code{healthy}, \code{"mild"}, \code{"severe"})}
#' }
"patients"
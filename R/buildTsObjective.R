## hydromad: Hydrological Modelling and Analysis of Data
##
## Copyright (c) Felix Andrews <felix@nfrac.org>
##

## aspects:
## * aggregation groups (regular / events) & aggregation function
## * reference model
## * data transformation



#' Generate objective functions with aggregation, transformation and a
#' reference model
#'
#' Generate objective functions with temporal aggregation, data transformation
#' and an optional reference model.
#'
#' @importFrom car powerTransform bcPower
#' @importFrom stats dnorm na.omit
#'
#' @aliases buildTsObjective buildObjectiveFun buildTsLikelihood
#' @param Q observed data, typically a \code{\link{zoo}} object.
#' @param groups an optional grouping variable, of the same length as \code{Q},
#' to aggregate the observed, fitted and reference time series. This can be a
#' \code{\link{factor}}, or a plain vector. It can also be a \code{zoo} object
#' with \code{factor}-type \code{coredata}, in which case it will be matched
#' with corresponding times in \code{Q}, etc.  Typically \code{groups} would be
#' generated by \code{\link{cut.Date}} (for regular time periods) or
#' \code{\link{eventseq}} (for events). See examples.
#' @param FUN, the aggregation function (and any extra arguments) to use on
#' each group when \code{groups} is specified. The actual aggregation is done
#' by \code{\link{eventapply}}.
#' @param ... Placeholder
# @param list() the aggregation function (and any extra arguments) to use on
# each group when \code{groups} is specified. The actual aggregation is done
# by \code{\link{eventapply}}.
#' @param ref output from a reference model correponding to \code{Q}. This is
#' passed, after any aggregation and/or transformation, to
#' \code{\link{nseStat}}. If left as \code{NULL}, the mean (of
#' aggregated/transformed data) is used.
#' @param boxcox,start if \code{boxcox = TRUE}, each dataset will be
#' transformed with a Box-Cox transformation (see \code{\link[car]{bcPower}}).
#' The power is estimated from the observed series \code{Q} (after any
#' aggregation) by \code{\link[car]{powerTransform}}. Alternatively the power
#' can be specified as the value of the \code{boxcox} argument.  Note that
#' \code{boxcox = 0} is a log transform. The offset is specified as the
#' \code{start} argument; if \code{NULL} it defaults to the 10 percentile (i.e.
#' lowest decile) of the non-zero values of \code{Q}.
#' @param distribution Placeholder
#' @param outliers Placeholder
#' @return \code{buildTsObjective} returns a \code{function}, which can be
#' passed arguments \code{Q, X, ...} (the standard signature for hydromad
#' objective functions). The \code{Q} argument is ignored since it was already
#' specified directly to \code{buildTsObjective}: i.e. the returned function is
#' only valid on the same dataset \code{Q} with corresponding fitted values
#' \code{X}. Further arguments to the returned function will be passed on to
#' \code{\link{nseStat}} (therefore the objective function is to be maximised,
#' not minimised).  If \code{boxcox = TRUE} was specified, the estimated
#' Box-Cox power can be extracted from the returned function \code{f} by
#' \code{environment(f)$lambda} and similarly for the offset value
#' \code{start}.
#' @author Felix Andrews \email{felix@@nfrac.org}
#' @seealso \code{\link{nseStat}}, \code{\link{eventseq}},
#' \code{\link{cut.Date}}, \code{\link{hydromad.stats}}
#' @keywords utilities optimization
#' @examples
#'
#' data(Cotter)
#' dat <- window(Cotter, start = "1990-01-01", end = "1993-01-01")
#'
#' ## use Box-Cox transform with parameters estimated from Q
#' objfun <- buildTsObjective(dat$Q, boxcox = TRUE)
#' objfun(X = dat$Q + 10)
#' ## extract the estimated Box-Cox parameters
#' lambda <- environment(objfun)$lambda
#' start <- environment(objfun)$start
#'
#' require(car)
#' qqmath(~ bcPower(dat$Q + start, lambda))
#' ## in this case the result is the same as:
#' nseStat(
#'   bcPower(dat$Q + start, lambda),
#'   bcPower(dat$Q + 10 + start, lambda)
#' )
#'
#' ## use monthly aggregation and log transform (Box-Cox lambda = 0)
#' objfun <- buildTsObjective(dat$Q,
#'   groups = cut(time(dat), "months"),
#'   FUN = sum, boxcox = 0
#' )
#' objfun(X = dat$Q + 10)
#' @export
buildTsObjective <-
  function(Q, groups = NULL, FUN = sum, ...,
           ref = NULL, boxcox = FALSE, start = NULL) {
    attributesQ <- attributes(Q)
    doaggr <- identity
    if (!is.null(groups)) {
      argsForFUN <- list(...)
      fullFUN <- function(...) {
        do.call(FUN, modifyList(list(...), argsForFUN))
      }
      doaggr <- function(x) {
        eventapply(x, groups, FUN = fullFUN)
      }
    }
    aggrQ <- doaggr(Q)
    aggrRef <- NULL
    if (!is.null(ref)) {
      aggrRef <- doaggr(ref)
    }
    if (!identical(boxcox, FALSE) && (length(aggrQ) > 1)) {
      coreaggrQ <- coredata(na.omit(aggrQ))
      if (is.null(start)) {
        start <-
          quantile(coreaggrQ[coreaggrQ > 0], 0.1, names = FALSE)
      }
      if (isTRUE(boxcox)) {
        lambda <- coef(powerTransform(coreaggrQ + start))
      } else {
        stopifnot(is.numeric(boxcox))
        lambda <- boxcox
      }
      function(Q, X, ...) {
        nseStat(aggrQ, doaggr(X),
          ref = aggrRef, ...,
          trans = function(x) bcPower(x + start, lambda)
        )
      }
    } else {
      function(Q, X, ...) {
        if (!missing(Q)) {
          if (!identical(attributes(Q), attributesQ)) {
            warning("'Q' has different attributes to that passed to buildTsObjectiveFun()")
          }
        }
        ## TODO: check that this 'Q' has same shape / index as original 'Q'?
        nseStat(aggrQ, doaggr(X), ref = aggrRef, ...)
      }
    }
  }

#' @rdname buildTsObjective
#' @export
buildTsLikelihood <-
  function(Q, groups = NULL, FUN = sum, ...,
           boxcox = FALSE, start = NULL,
           distribution = dnorm, outliers = 0) {
    doaggr <- identity
    trans <- identity
    if (!is.null(groups)) {
      argsForFUN <- list(...)
      fullFUN <- function(...) {
        do.call(FUN, modifyList(list(...), argsForFUN))
      }
      doaggr <- function(x) {
        eventapply(x, groups, FUN = fullFUN)
      }
    }
    aggrQ <- doaggr(Q)
    if (!identical(boxcox, FALSE) && (length(aggrQ) > 1)) {
      coreaggrQ <- coredata(na.omit(aggrQ))
      if (is.null(start)) {
        start <-
          quantile(coreaggrQ[coreaggrQ > 0], 0.1, names = FALSE)
      }
      if (isTRUE(boxcox)) {
        lambda <- coef(powerTransform(coreaggrQ + start))
      } else {
        stopifnot(is.numeric(boxcox))
        lambda <- boxcox
      }
      trans <- function(x) {
        x[] <- bcPower(x + start, lambda)
        x
      }
    }
    function(Q, X) {
      resids <- trans(aggrQ) - trans(doaggr(X))
      logp <- distribution(resids, log = TRUE)
      if (outliers > 0) {
        logp <- tail(sort(logp), -outliers)
      }
      sum(logp)
    }
  }

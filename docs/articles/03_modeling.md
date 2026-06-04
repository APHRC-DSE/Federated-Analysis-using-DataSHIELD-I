# Federated regression on an extracted table

> Every result on this page was produced by executing the code against
> the live three-site federation (repository steps 1–4). Connection
> parameters are read from the gitignored `sites.env`.

Because a dsOMOP extract is just an ordinary server-side data frame, the
whole `dsBaseClient` modelling toolchain applies to it directly. Here we
re-create the demographics extract, recode sex into a 0/1 indicator,
assemble a model frame, and fit federated generalised linear models.
Only the models’ sufficient statistics are pooled across the three sites
— no patient row ever leaves a server.

## Log in, attach, and re-extract the demographics table

``` r

library(DSI); library(DSOpal); library(dsBaseClient); library(dsOMOPClient)

find_up <- function(f, d = getwd()) {
  repeat {
    p <- file.path(d, f); if (file.exists(p)) return(p)
    up <- dirname(d); if (identical(up, d)) stop(f, " not found"); d <- up
  }
}
read_env <- function(path) {
  ln <- trimws(readLines(path, warn = FALSE))
  ln <- ln[nzchar(ln) & !startsWith(ln, "#")]
  e <- list()
  for (kv in regmatches(ln, regexec("^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", ln)))
    if (length(kv) == 3L) e[[kv[2]]] <- kv[3]
  e
}
cfg <- read_env(Sys.getenv("SITES_ENV", unset = find_up("sites.env")))

builder <- DSI::newDSLoginBuilder()
for (S in sub("_OPAL_URL$", "", grep("_OPAL_URL$", names(cfg), value = TRUE)))
  builder$append(server = tolower(S), url = cfg[[paste0(S, "_OPAL_URL")]],
                 user = cfg$OPAL_USER, password = cfg$OPAL_PASSWORD,
                 resource = cfg$OPAL_RESOURCE_PATH,
                 driver = "OpalDriver", profile = cfg$OPAL_PROFILE)
conns <- DSI::datashield.login(logins = builder$build())
ds.omop.connect(resource = cfg$OPAL_RESOURCE_PATH, symbol = "omop", conns = conns)

plan <- ds.omop.plan()
plan <- ds.omop.plan.person_level(
  plan,
  tables = list(person = c(sex = "gender_concept_id", birth_year = "year_of_birth")),
  name = "demographics")
ds.omop.plan.execute(plan, out = c(demographics = "D"), symbol = "omop", conns = conns)
```

## Assemble a model frame

OMOP encodes sex as a concept id (8507 male, 8532 female). We recode it
to a 0/1 `male` indicator and bind it onto the extract to form the model
frame `DF`:

``` r

ds.recodeValues(var.name = "D$sex",
                values2replace.vector = c(8507, 8532),
                new.values.vector    = c(1, 0),
                newobj = "male", datasources = conns)
ds.dataFrame(x = c("D", "male"), newobj = "DF", datasources = conns)
```

``` r

ds.colnames("DF")[[1]]
#> [1] "sex"        "birth_year" "male"
```

## Linear model: birth year by sex

A Gaussian GLM of `birth_year ~ male`, pooled across all three sites.
With a single 0/1 predictor the intercept is the mean birth year of
women and the slope is the men-minus-women difference, so the fit is
directly interpretable:

``` r

g <- ds.glm(formula = "DF$birth_year ~ DF$male", family = "gaussian",
            datasources = conns)
g$coefficients
#>                 Estimate Std. Error      z-value   p-value    low0.95CI
#> (Intercept) 1957.8514202  0.4362186 4488.2344511 0.0000000 1956.9964475
#> DF$male        0.4385116  0.6229477    0.7039301 0.4814763   -0.7824434
#>              high0.95CI
#> (Intercept) 1958.706393
#> DF$male        1.659467
```

## Logistic model: sex by birth year

The same model frame supports a binomial GLM just as readily:

``` r

gb <- ds.glm(formula = "DF$male ~ DF$birth_year", family = "binomial",
             datasources = conns)
gb$coefficients
#>                  Estimate  Std. Error    z-value   p-value low0.95CI.LP
#> (Intercept)   -3.32848244 4.672977755 -0.7122830 0.4762896 -12.48735054
#> DF$birth_year  0.00168016 0.002386432  0.7040469 0.4814036  -0.00299716
#>               high0.95CI.LP      P_OR low0.95CI.P_OR high0.95CI.P_OR
#> (Intercept)      5.83038566 0.0346069   3.774078e-06       0.9970717
#> DF$birth_year    0.00635748 1.0016816   9.970073e-01       1.0063777
```

## Disconnect

``` r

ds.omop.disconnect(symbol = "omop", conns = conns)
DSI::datashield.logout(conns)
```

The models above are standard `dsBaseClient` fits computed on a dsOMOP
extract: the OMOP layer produced the analysis dataset, and the ordinary
federated toolchain took it from there.

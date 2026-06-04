# Extracting a tailored analysis dataset

> Every result on this page was produced by executing the code against
> the live three-site federation (repository steps 1–4). Connection
> parameters are read from the gitignored `sites.env`.

dsOMOP’s plan DSL lets you request *exactly* the columns you want — and
rename them on the way out — then materialises a single person-level
data frame on each server. The table is built in place; nothing
patient-level is transferred. We then use standard `dsBaseClient` to
confirm the extract has landed as an ordinary server-side R data frame,
and explore it.

## Log in and attach the OMOP resource

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
```

## Build and execute an extraction plan

We ask for two `person` columns and rename them as we extract:
`gender_concept_id` becomes `sex` and `year_of_birth` becomes
`birth_year`. The plan is executed on each server, producing a
server-side data frame bound to the symbol `D`.

``` r

plan <- ds.omop.plan()
plan <- ds.omop.plan.person_level(
  plan,
  tables = list(person = c(sex = "gender_concept_id", birth_year = "year_of_birth")),
  name = "demographics")

ds.omop.plan.execute(plan, out = c(demographics = "D"), symbol = "omop", conns = conns)
```

## Confirm the extract landed as a server-side data frame

The columns are exactly the two we asked for, under their new names —
and no identifier column came along:

``` r

ds.colnames("D")
#> $aphrc
#> [1] "sex"        "birth_year"
#> 
#> $dgh
#> [1] "sex"        "birth_year"
#> 
#> $iressef
#> [1] "sex"        "birth_year"
```

Its dimensions, pooled across the three sites, recover the full cohort
of 2 694 persons:

``` r

ds.dim("D", type = "combine")
#> $`dimensions of D in combined studies`
#> [1] 2694    2
```

[`ds.summary()`](https://rdrr.io/pkg/dsBaseClient/man/ds.summary.html)
reports `D` as an ordinary `data.frame` — this is the point where the
OMOP layer hands off to the standard DataSHIELD toolchain:

``` r

ds.summary("D")[[1]]
#> $class
#> [1] "data.frame"
#> 
#> $`number of rows`
#> [1] 889
#> 
#> $`number of columns`
#> [1] 2
#> 
#> $`variables held`
#> [1] "sex"        "birth_year"
```

## Explore the extracted variable

From here we use plain `dsBaseClient`. The pooled mean and quantiles of
`birth_year` combine sufficient statistics from all three sites:

``` r

ds.mean("D$birth_year", type = "combine")$Global.Mean
#>                 EstimatedMean Nmissing Nvalid Ntotal
#> studiesCombined      1958.066        0   2694   2694
```

``` r

ds.quantileMean("D$birth_year", type = "combine")
#>       5%      10%      25%      50%      75%      90%      95%     Mean 
#> 1922.941 1936.982 1949.642 1960.656 1970.000 1976.000 1979.000 1958.066
```

## Disconnect

``` r

ds.omop.disconnect(symbol = "omop", conns = conns)
DSI::datashield.logout(conns)
```

The extract is now an ordinary federated data frame. The [next
page](https://aphrc-dse.github.io/Federated-Analysis-using-DataSHIELD-I/articles/03_modeling.md)
fits a regression model on it with `ds.glm`.

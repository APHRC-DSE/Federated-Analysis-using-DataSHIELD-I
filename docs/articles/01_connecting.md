# Connecting to the federation

> Every result on this page was produced by executing the code against
> the live three-site federation. To reproduce it, run repository steps
> 1–4 first, then rebuild this site. Connection parameters are read from
> the gitignored `sites.env`; the credentials it holds are the public
> demo credentials.

This page logs the DataSHIELD client into the three sites of the local
federation (`aphrc`, `dgh`, `iressef`), attaches the OMOP CDM resource
on each, and explores what every site holds — using dsOMOP’s *aggregate*
functions, which return only disclosure-checked metadata. No
patient-level data is transferred.

## Log in and attach the OMOP resource

The login parameters (site URLs, the resource path, and the demo
credentials) are written to `sites.env` by repository steps 2–4, so we
read them rather than hard-coding anything.

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

# Attach the OMOP CDM resource on every server and initialise dsOMOP.
ds.omop.connect(resource = cfg$OPAL_RESOURCE_PATH, symbol = "omop", conns = conns)
```

The client is now connected to all three sites:

``` r

names(conns)
#> [1] "aphrc"   "dgh"     "iressef"
```

## What tables does each site expose?

dsOMOP discovers tables at runtime by introspecting the CDM schema — it
does not hard-code an OMOP version. Here are the tables visible on the
first site:

``` r

tabs <- ds.omop.tables(symbol = "omop", conns = conns)
head(tabs[[1]], 12)
#>              table_name schema_category has_person_id concept_prefix
#> 1                person             CDM          TRUE         gender
#> 2    observation_period             CDM          TRUE    period_type
#> 3      visit_occurrence             CDM          TRUE          visit
#> 4          visit_detail             CDM          TRUE   visit_detail
#> 5  condition_occurrence             CDM          TRUE      condition
#> 6         drug_exposure             CDM          TRUE           drug
#> 7  procedure_occurrence             CDM          TRUE      procedure
#> 8       device_exposure             CDM          TRUE         device
#> 9           measurement             CDM          TRUE    measurement
#> 10          observation             CDM          TRUE    observation
#> 11                death             CDM          TRUE          death
#> 12                 note             CDM          TRUE           note
```

And the columns of the `person` table:

``` r

ds.omop.columns("person", symbol = "omop", conns = conns)[[1]]
#>                    column_name cdm_datatype                 db_datatype
#> 1                    person_id      integer                     integer
#> 2            gender_concept_id      integer                     integer
#> 3                year_of_birth      integer                     integer
#> 4               month_of_birth      integer                     integer
#> 5                 day_of_birth      integer                     integer
#> 6               birth_datetime     datetime timestamp without time zone
#> 7              race_concept_id      integer                     integer
#> 8         ethnicity_concept_id      integer                     integer
#> 9                  location_id      integer                     integer
#> 10                 provider_id      integer                     integer
#> 11                care_site_id      integer                     integer
#> 12         person_source_value  varchar(50)           character varying
#> 13         gender_source_value  varchar(50)           character varying
#> 14    gender_source_concept_id      integer                     integer
#> 15           race_source_value  varchar(50)           character varying
#> 16      race_source_concept_id      integer                     integer
#> 17      ethnicity_source_value  varchar(50)           character varying
#> 18 ethnicity_source_concept_id      integer                     integer
#>         concept_role fk_domain is_date is_sensitive is_blocked
#> 1        non_concept             FALSE        FALSE      FALSE
#> 2     domain_concept    Gender   FALSE        FALSE      FALSE
#> 3        non_concept             FALSE        FALSE      FALSE
#> 4        non_concept             FALSE        FALSE      FALSE
#> 5        non_concept             FALSE        FALSE      FALSE
#> 6        non_concept              TRUE        FALSE      FALSE
#> 7  attribute_concept      Race   FALSE        FALSE      FALSE
#> 8  attribute_concept Ethnicity   FALSE        FALSE      FALSE
#> 9        non_concept             FALSE        FALSE      FALSE
#> 10       non_concept             FALSE        FALSE      FALSE
#> 11       non_concept             FALSE        FALSE      FALSE
#> 12       non_concept             FALSE         TRUE       TRUE
#> 13       non_concept             FALSE         TRUE       TRUE
#> 14    source_concept    Gender   FALSE         TRUE       TRUE
#> 15       non_concept             FALSE         TRUE       TRUE
#> 16    source_concept      Race   FALSE         TRUE       TRUE
#> 17       non_concept             FALSE         TRUE       TRUE
#> 18    source_concept Ethnicity   FALSE         TRUE       TRUE
```

## Federated row and person counts

[`ds.omop.table.stats()`](https://rdrr.io/pkg/dsOMOPClient/man/ds.omop.table.stats.html)
returns disclosure-checked row counts and *distinct-person* counts for
each site. The GiBleed cohort is sharded by person into disjoint slices,
so the pooled distinct-person count is the sum across sites — and for
the `person` table it reconstructs the whole cohort (2 694), without any
site exposing more than its own shard.

``` r

sites <- names(conns)
tbls  <- c("person", "condition_occurrence", "drug_exposure", "measurement")

per_site <- lapply(tbls, function(tb)
  ds.omop.table.stats(tb, symbol = "omop", conns = conns)$per_site)
names(per_site) <- tbls

tabulate_field <- function(field) {
  m <- t(vapply(per_site, function(ps)
    vapply(sites, function(s) as.numeric(ps[[s]][[field]]), numeric(1)),
    numeric(length(sites))))
  colnames(m) <- sites
  cbind(m, pooled = rowSums(m))
}
```

Distinct persons per table — the `person` row is the full cohort, and
the event tables show how many of those persons have records of each
kind:

``` r

tabulate_field("persons")
#>                      aphrc dgh iressef pooled
#> person                 889 878     927   2694
#> condition_occurrence   889 878     927   2694
#> drug_exposure          889 878     927   2694
#> measurement            885 875     926   2686
```

Total rows per table:

``` r

tabulate_field("rows")
#>                      aphrc   dgh iressef pooled
#> person                 889   878     927   2694
#> condition_occurrence 21470 20983   22879  65332
#> drug_exposure        22348 21946   23413  67707
#> measurement          14214 13852   15987  44053
```

## Most prevalent conditions, pooled across sites

[`ds.omop.concept.prevalence()`](https://rdrr.io/pkg/dsOMOPClient/man/ds.omop.concept.prevalence.html)
ranks concepts by the number of distinct persons who have them,
combining the three shards into a single pooled ranking. A concept
receives a pooled count only when every shard reports it, so we show the
conditions whose pooled count is complete across all sites.

``` r

prev <- ds.omop.concept.prevalence(
  "condition_occurrence", metric = "persons", top_n = 10,
  scope = "pooled", symbol = "omop", conns = conns)

subset(prev$pooled, !suppressed, select = c("concept_name", "n_persons"))
#>                concept_name n_persons
#> 1            Osteoarthritis      2694
#> 2           Viral sinusitis      2686
#> 3   Acute viral pharyngitis      2606
#> 4          Acute bronchitis      2543
#> 5              Otitis media      2025
#> 6 Streptococcal sore throat      1677
#> 7           Sprain of ankle      1357
```

## Disconnect

``` r

ds.omop.disconnect(symbol = "omop", conns = conns)
DSI::datashield.logout(conns)
```

Everything above came back as aggregates. The [next
page](https://aphrc-dse.github.io/Federated-Analysis-using-DataSHIELD-I/articles/02_extraction.md)
extracts a person-level table — still entirely server-side — and
confirms it landed as an ordinary R data frame.

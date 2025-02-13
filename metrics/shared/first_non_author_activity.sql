with issues as (
  select distinct id,
    user_id,
    created_at
  from
    gha_issues
  where
    is_pull_request = true
    and created_at >= '{{from}}'
    and created_at < '{{to}}'
    and (lower(dup_user_login) {{exclude_bots}})
), prs as (
  select distinct id,
    user_id,
    created_at
  from
    gha_pull_requests
  where
    created_at >= '{{from}}'
    and created_at < '{{to}}'
    and (lower(dup_user_login) {{exclude_bots}})
), tdiffs as (
  select extract(epoch from i2.updated_at - i.created_at) / 3600 as diff,
    r.repo_group as repo_group
  from
    issues i,
    gha_repo_groups r,
    gha_issues i2
  where
    i.id = i2.id
    and r.name = i2.dup_repo_name
    and r.id = i2.dup_repo_id
    and (lower(i2.dup_actor_login) {{exclude_bots}})
    and i2.created_at >= '{{from}}'
    and i2.created_at < '{{to}}'
    and i2.event_id in (
      select event_id
      from
        gha_issues sub
      where
        sub.dup_actor_id != i.user_id
        and sub.id = i.id
        and sub.created_at >= '{{from}}'
        and sub.created_at < '{{to}}'
        and sub.updated_at > i.created_at + '30 seconds'::interval
        and sub.dup_type like '%Event'
      order by
        sub.updated_at asc
      limit 1
    )
  union select extract(epoch from p2.updated_at - p.created_at) / 3600 as diff,
    r.repo_group as repo_group
  from
    prs p,
    gha_repo_groups r,
    gha_pull_requests p2
  where
    p.id = p2.id
    and r.name = p2.dup_repo_name
    and r.id = p2.dup_repo_id
    and (lower(p2.dup_actor_login) {{exclude_bots}})
    and p2.created_at >= '{{from}}'
    and p2.created_at < '{{to}}'
    and p2.event_id in (
      select event_id
      from
        gha_pull_requests sub
      where
        sub.dup_actor_id != p.user_id
        and sub.id = p.id
        and sub.created_at >= '{{from}}'
        and sub.created_at < '{{to}}'
        and sub.updated_at > p.created_at + '30 seconds'::interval
        and sub.dup_type like '%Event'
      order by
        sub.updated_at asc
      limit 1
    )
)
select
  'non_auth;All;p15,med,p85' as name,
  percentile_disc(0.15) within group (order by diff asc) as non_author_15_percentile,
  percentile_disc(0.5) within group (order by diff asc) as non_author_median,
  percentile_disc(0.85) within group (order by diff asc) as non_author_85_percentile
from
  tdiffs
union select 'non_auth;' || repo_group || ';p15,med,p85' as name,
  percentile_disc(0.15) within group (order by diff asc) as non_author_15_percentile,
  percentile_disc(0.5) within group (order by diff asc) as non_author_median,
  percentile_disc(0.85) within group (order by diff asc) as non_author_85_percentile
from
  tdiffs
where
  repo_group is not null
group by
  repo_group
order by
  non_author_median desc,
  name asc
;

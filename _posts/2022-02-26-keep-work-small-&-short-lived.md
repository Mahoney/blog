---
layout: post
title: Keep Work Small & Short-lived
date: '2022-02-26T11:56:12.000+0000'
author: Robert Elliot
tags:
---

I've been mulling some agile ideas. Specifically, trunk based development and a
zero bug / no bug-database policy.

I've experienced both - I was on a project with upwards of 15 devs, doing
routine TDD on trunk with a zero bug policy - they were raised as physical pink
index cards on a physical board, and always went to the top, so there were the
next bit of work picked up.

My insight is that actually we _were_ bug tracking with a bug database. The bug
database was the physical cards. And we had bugs, so it wasn't a zero bugs
policy. What it was, was a _very short-lived_ bug policy - we tolerated &
tracked them for a very short period of time.

And the same was true of our trunk based development - we did branch. As soon as
a pair diverged from trunk on their work station, we had a branch, just locally
on that work station - and it needed to be merged by pushing to trunk (and
sometimes, of course, that caused merge conflicts that had to be resolved). But
crucially, those branches were _very short-lived_. Because they only existed
locally we expected to merge them into trunk multiple times a day.

My theory is that the two practises are actually not in themselves the silver
bullet, and indeed may represent local maxima. The real benefits are branches
and tracked bugs that are short-lived. The pros of the TBD & zero bugs
practises is that it makes it very difficult _not_ to have those benefits. If
you track your bugs as physical index cards on a physical board they can't live
for long - you'll have to fix them or throw them away. If you only branch onto
local machines no-one else can cherry-pick or merge in your changes, and you're
in danger of losing them to some hardware failure, so there's a huge incentive
to get your stuff on trunk ASAP.

However, if you can find a way to have those benefits whilst having remote
branches & keeping bugs in a tracking system you may be able to get other
benefits. I like a protected trunk/main branch - when doing TBD the build got
broken from time to time, and it held everyone else up (the classic 5:30 cowboy
check-in & run...). Set the CI up to auto-merge on successful build and you
mitigate that a lot without adding much overhead - provided you keep the branch
short-lived.


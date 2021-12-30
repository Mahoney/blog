---
layout: post
title: Log4Shell & small modules
date: '2021-12-30T12:29:18.000+0000'
author: Robert Elliot
tags:
---

TLDR: if capabilities are kept in separate modules it mitigates the risk of a
capability being compromised.

Everyone's talking about Log4Shell. A lot of the talk is, of course, about the
nature of code injection attacks, and the failure to separate code and data.
It's an area where I feel sympathy for the Log4J 2 devs - I think the mistake
they made is a terrifyingly easy one to make, as every SQL injection or naked
`eval` regularly demonstrates. Layers of abstraction can lead to forgetting when
an input to a function is now untrusted data.

However, I think there's another aspect of it that deserves consideration - the
fact that the ability to do this was installed on so many systems.

How many systems need to do LDAP JNDI lookups at all? I'm guessing a pretty
small percentage. How many need to do so from their logging system? A smaller
percentage. And of those, how many need to load complex classes (with static
initialisation) from a remote location via their logging system? I'm guessing an
absolutely _tiny_ fraction of the systems vulnerable to Log4shell were actually
benefiting from the feature(s) that caused the vulnerability.

And yet there the code was, sitting on all those systems, waiting for the moment
someone found the vulnerability.

I've been experimenting with JPMS and jlink, and if you create a JRE without the
`java.naming` module then, unsurprisingly, you aren't vulnerable to Log4Shell
even if you're running an old Log4J 2 version. But inertia and a reasonably high
barrier to entry means that adoption of JPMS in general, and adoption of jlink
cut down JREs in particular, has been pretty minimal, unfortunately. And some of
the `java` namespaced modules are still disconcertingly enormous - for instance
using Java Beans (as lots of things, including Log4J 2, require) means bringing
in `java.desktop`, which brings in the `swing`, `awt` & `applet` packages
amongst others. Perhaps rather more than you expected to call `set` on some data
class...

However, this could have been managed at the Log4J 2 level. `JndiManager` is in
the `org.apache.logging.log4j.core.net` package in the `log4j-core` jar, along
with rather a lot of things capable of doing I/O over multiple protocols. So you
can't use Log4J 2 without having this logic installed. Had JNDI lookups been in
its own little jar, brought in as a separate dependency, the bug would still
have been in that code - but I'd hazard a guess that it would have been
drastically mitigated because most systems would not have had it sitting there,
a little otherwise pointless time bomb waiting to explode.

There's a tension here with ease of use, and particularly keeping a low
barrier to entry. It _is_ nice when it turns out you can just use a feature
without scrabbling around trying to work out which dependency you need to add to
get it to work. But having so many features lying around unused can have a high
price.

Keep it small. Keep it focussed. Leave it out by default. If you need a feature
99% of users do not need, it is entirely reasonable that you should need to add
a new dependency for it to start working.

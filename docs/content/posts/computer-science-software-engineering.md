+++
title = "Computer Science & Software Engineering"
author = ["shane"]
date = 2025-03-10T18:17:00-06:00
draft = false
+++

I wrote this post to easily reference a concept that I find myself explaining
frequently to software engineers.

The concept is simple: <span class="underline">computer science is not software engineering</span>. By itself,
the statement seems obviously true. Unfortunately our industry has a problem with conflating the two
in a way that leads to bad outcomes in the products engineers create.


## An analogy with cars {#an-analogy-with-cars}

I like to compare it to the difference between
physics and mechanical engineering. I have no doubt that physics is an extremely important
part of mechanical engineering. I want the folks designing my cars to actually know certain
areas of physics pretty well. However when it comes to designing cars there are areas outside of
physics that engineers are trained to consider. One example from my freshman engineering classes: In
addition to science, engineering typically involves cost benefit analysis over the lifecycle of products.

Like any real world conversation, it's more nuanced than saying "scientists write papers and discover knowledge" and
"engineers use science to build things", but that's a decent first approximation. Scientists often
do have to care about costs, sometimes they are researching new techniques that reduce cost. Engineers care about science,
sometimes the work they are doing do tackle new problems results in new science being created. But I hope you'll agree
it's still fair to say: Science and Engineering are different disciplines.


## How this applies to CS/SWE {#how-this-applies-to-cs-swe}

It's common in the tech industry to hire CS graduates as software engineers. In my experience the reasons why
are:

-   CS grads have tools to avoid certain catastrophic performance cliffs due to big O complexity.
-   CS grads and some other "hard science" or math degrees are considered to be evidence of being "smart enough" to do SWE work.

Just like in the physics/mechanical engineering example above, I want the people
building my apps and services to know some computer science. In addition I want them to understand engineering tradeoffs. Bizarrely,
I find a lot of SWEs consider these tradeoffs to be "political" or "non-technical" such as choosing a framework based on
size of developer population using it or availability of commercial support. A good example of this might be Linux vs FreeBSD.
There are arguments that `FreeBSD` is technically superior, especially in areas like their `ktls` implementation,
but when looking at availability of expertise and support I believe `Linux` will have more available.
Netflix has some workloads that are essentially a `ktls` and `sendfile` benchmark, and they serve
content at a large scale and `FreeBSD` seems to be a great choice for them. For many other
companies `Linux` makes more sense due to features and support. Seems like
it would be an uphill battle basing your `k8s` SaaS on `FreeBSD`.


## The point {#the-point}

What I'd like to leave you with is a reminder that, when it comes to working as a software engineer, having decent
CS knowledge is necessary but not sufficient. Try to keep an open mind about what individual engineers bring to the
table because god knows we need more people who can deal with cost benefit analysis and large projects and people. You know,
the things that <span class="underline">actually</span> cause most engineering projects to fail.

---
title: Scent of a Language
author: AgentM
---

# Scent of a Language

Do you remember a moment when you realized that a programming environment you once revered no longer looks appealing? Perhaps you noticed that a programming language forced you into copy-pasting or that an obvious feature was missing but was provided in another language.

While a codebase in any language may have a "[code smell](https://en.wikipedia.org/wiki/Code_smell)", programming languages themselves may have permanent "language smells". Language smells are more devastating than regular code smells because programming languages typically:

* do not offer a workaround while a code smell can be refactored away
* the cost to resolve the smell is to switch programming languages, which is almost always too high a cost

## Sources
Language smells can have many sources, but among them are:

1. design-by-committee (e.g. SQL) which can lead to
 * intentional hobbling by industry meddling
 * compromise design patterns based on existing legacy designs
 * exclusion of useful design patterns due to disagreement
 * lengthy standardization tracks which delay language fixes
1. business-guided deprecation (e.g. many Google or Apple frameworks and services)
 * cause frameworks to be prematurely abandoned due to internal politics
 * cause third-party code relying on the framework to come to an unexpected dead end
1. deprecated modules (e.g. PHP or Java)
 * lead to unnecessary refactoring
 * prevent version upgrades
1. internally inconsistent designs (e.g. [many undefined C behaviors](http://blog.regehr.org/archives/213))
 * lead to cross-compiler or cross-platform surprises
 * force unnecessary workarounds or testing
1. overexpressiveness (e.g. NULL in many languages)
 * the programmer must always be wary of the footgun which cannot be disabled
 * loose compilers allow programs to be expressed which need not be expressed resulting in unhandled runtime surprises
1. underexpressiveness (e.g. the need for a C macro language, Template Haskell)
 * forcing programmers to learn a new language to make up for the weaknesses in the original language

The analogy with a foundation fits exactly- if one chooses to build on a flimsy foundation, no matter how many programmers are propping it up, the higher-level constructs must ultimately fail.

## Language Requirements

To resolve the above smells, the programming language must offer:

* consistent mathematical foundations (instead of design-by-committee) to mitigate legacy APIs and technical debt
* no control by a singular entity which can force deprecation
 * this point favors open-source platforms
* programming constructs which neither include footguns (overexpressiveness) nor language construct cliffs (underexpressiveness)
* a complete platform which covers your application's future features
* a long-term development future or strategy
 * a tacit admission that you or your company is not suited or equipped to maintain a programming platform
   * don't laugh- many companies have made this mistake. Choosing a programming platform is an investment many companies are fearful to make but they underestimate the cost of maintaining a platform.

At this point, the cynical programmer may claim: "If two programming languages are Turing complete, they are logically equivalent. So we should merely choose the platform with the greatest number of users since that seems to imply the best longevity of the platform." However, a long-term strategy only mitigates fear of an unmaintained platform and speaks nothing of the quality of the project (e.g. consider Visual Basic) or if the maintainer will continue to maintain it.

## Next Time

In part 2 of this series, I will describe how choosing Haskell- as both a language and platform- over other platforms for Project:M36 (a relational algebra engine) allowed us to leapfrog other database management system designs.

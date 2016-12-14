---
title: On Isomorphic Schemas
author: AgentM
---

Isomorphic schemas in Project:M36 aim to solve view-updating
inconsistencies as covered in Date's "View Updating and Relational
Theory". Project:M36 accomplishes this by providing schema building
blocks which can only result in isomorphic schemas, thus eliminating the
possibility of violations of the Information Principle and the Principle
of Interchangeability.

Consider the following example in TutorialD:

```
TutorialD (master/main): employee:=relation{tuple{name "Steve", boss
""}, tuple{name "Cindy", boss "Steve"}, tuple{name "Sam", boss "Steve"}}
TutorialD (master/main): :addschema splitboss (isounion "boss" "peon"
"employee" boss="", isopassthrough "true", isopassthrough "false")
```

At this point, we have created a secondary schema "splitboss" isomorphic
to the "main" schema based on a restriction predicate. Let's examine it:

```
TutorialD (master/main): :setschema splitboss
TutorialD (master/splitboss): :showexpr employee
ERR: RelVarNotDefinedError "employee"
```

The employee relation variable does not exist in this context because
that would violate the Principle of Interchangeability.

```
TutorialD (master/splitboss): :showexpr peon
┌──────────┬──────────┐
│boss::Text│name::Text│
├──────────┼──────────┤
│"Steve"   │"Sam"     │
│"Steve"   │"Cindy"   │
└──────────┴──────────┘
TutorialD (master/splitboss): :showexpr boss
┌──────────┬──────────┐
│boss::Text│name::Text│
├──────────┼──────────┤
│""        │"Steve"   │
└──────────┴──────────┘
```

Let's add another boss:

```
TutorialD (master/splitboss): insert boss relation{tuple{name "Elvis",
boss ""}}
TutorialD (master/splitboss): :showexpr boss
┌──────────┬──────────┐
│boss::Text│name::Text│
├──────────┼──────────┤
│""        │"Steve"   │
│""        │"Elvis"   │
└──────────┴──────────┘
```

and confirm that this boss appears in the "main" schema as well:

```
TutorialD (master/splitboss): :setschema main
TutorialD (master/main): :showexpr employee
┌──────────┬──────────┐
│boss::Text│name::Text│
├──────────┼──────────┤
│""        │"Steve"   │
│"Steve"   │"Sam"     │
│"Steve"   │"Cindy"   │
│""        │"Elvis"   │
└──────────┴──────────┘
```

This example demonstrates just one of many possible isomorphic building
blocks. Currently, Project:M36 implements three: restriction, its
inverse union, and rename, but we plan to implement more in the future.
We don't plan to be able to generate every possible isomorphic
transformation, just ones that are practical.

I hope that this example whet your appetite to learn more. If so, please
read our [short paper with more details](https://github.com/agentm/project-m36/blob/master/docs/isomorphic_schemas.markdown).

Thanks for reading!

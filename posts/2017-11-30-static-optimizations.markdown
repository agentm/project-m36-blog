---
title: 10 Cool Static Relational Algebra Optimizations in Project:M36
author: AgentM
---

# 10 Cool Static Relational Algebra Optimizations in Project:M36

A few months ago, a jooq blog entry was posted called [10 Cool SQL Optimisations That do not Depend on the Cost Model](https://blog.jooq.org/2017/09/28/10-cool-sql-optimisations-that-do-not-depend-on-the-cost-model/#top3) which covered some SQL query rewrite optimizations which can unconditionally run faster than the original query. Because these query rewrites do not require inspecting the database state (the "cost model"), the optimizations the rewrites provide are implementation independent. They are often called "static optimizations".

In this blog entry, we will cover how the same optimizations apply to the Project:M36 relational algebra engine and why adherence to the mathematical underpinnings of the relational algebra make the optimizations more obvious, easier-to-understand, and ultimately, more performant in execution.

"Cost-model independent" optimizations are query rewrites which eliminate extraneous processing, implying that doing nothing is unconditionally "cheaper" (in a computation sense) than doing something. For example, in the TutorialD query `s where true`, it's obvious that the restriction cannot actually filter out any tuples, so executing the restriction is extraneous.

Let's examine the same optimizations that the jooq blog post covered.

## 1. Transitive Closure

If the relational restriction predicate `A` is identical to predicate `B`, and predicate `B` is identical to `C`, then `A` can be replaced with `C` (or vice versa). This is called the "transitive property" and can be used to replace obviously more expensive restriction predicates with cheaper versions.

In general, replacing a predicate with a static value (such as a text or integer value) is cheaper than looking up a value in a tuple or executing a function. For example:

```
s where a=@b and b=300
```

is optimized to:

```
s where a=300 and b=300
```

and the Haskell code to implement this is straightforward:

```haskell
let attrMap = findStaticRestrictionPredicates optPred in
pure (Right (replaceStaticAtomExprs optPred attrMap))
```

The [algebraic data type manipulation](https://github.com/agentm/project-m36/blob/master/src/lib/ProjectM36/StaticOptimizer.hs#L297) is elided for brevity, but it is entirely mechanical.

## 2. Impossible Predicates

When predicates are demonstrably and unconditionally false the restriction can be eliminated and replaced with an empty relation. For example, `s where false` returns the empty relation (no tuples) with the attributes of `s`.

Note that this optimization is more effective in the real relational algebra when compared to SQL. In Project:M36, there is no three-valued logic involving NULL, so `where true` and `where false` are inverses and the predicate is boolean-valued.

Project:M36 does not support predicates of the form "0 = 1" because such expression don't target the relational state, so the examples in the sister blog post cannot be represented.

The [implementation](https://github.com/agentm/project-m36/blob/master/src/lib/ProjectM36/StaticOptimizer.hs#L118) is simple.

```haskell
    | isFalseExpr optimizedPredicate2 -> do -- replace where false predicate with empty with attributes from relexpr
    attributesRel <- typeForRelationalExpr expr
      case attributesRel of
        Left err -> pure $ Left err
        Right attributesRelA -> pure $ Right $ MakeStaticRelation (attributes attributesRelA) emptyTupleSet
...
```

## 3. Join Elimination

If there is a foreign key constraint between a join condition and a projection on the resultant join includes the foreign key and not any attributes from the secondary relation variable, then the join can be elided. For example (from the C.J. Date relation variable examples):

```
(s join sp){s#,sname}
```

can be rewritten as

```
s{s#,sname}
```

This rewrite is valid because a foreign key constraint proves that there cannot be `s#` values in `sp` which do not already appear in `s`.

The [implementation](https://github.com/agentm/project-m36/blob/master/src/lib/ProjectM36/StaticOptimizer.hs#L322) is complicated here only because we need to confirm a specific foreign key constraint.

## 4. Removing Silly Predicates

In section 2, we covered `s where false`, but `s where true` is equally valid to remove. `s where true` is equivalent to `s` because the restriction is guaranteed to filter out any tuples.

The [implementation](https://github.com/agentm/project-m36/blob/master/src/lib/ProjectM36/StaticOptimizer.hs#L122) is almost trivial:

```haskell
| isTrueExpr optimizedPredicate2 -> applyStaticRelationalOptimization expr -- remove predicate entirely
```

## 5. Projections in Exists Subqueries

Project:M36 doesn't really have a notion of "subqueries" because we simply build up an algebraic data type representing the query, so it's obvious that relational expressions can be nested, but, in the special case of existence, Project:M36 already requires a projection on empty attributes:

```
(s rename {s# as sno}) where ((sp where ^gte(@qty,400) and sno=@s#){})
```

A projection on empty attributes must either result in `true` which is the relation with no attributes and one tuple or `false` which is the relation with no attributes and zero tuples.

A further optimization here could be to stop the restriction scan as soon as one tuple is found since the existence is then proven.

## 6. Predicate Merging

Simple predicate merging such `s where true and true` is supported, but more complicated merges such as those shown in the sister blog post are not yet supported.

The implementation is hardly worth mentioning:

```haskell
if optPred1 == optPred2 then
  pure (Right optPred1)
  else
  pure (Right (AndPredicate optPred1 optPred2))
```

A similar boolean short-circuit optimization is offered for `or` predicates.

## 7. Provably Empty Sets

This set of optimizations uses constraints to determine if a restriction is universally true or false in order to eliminate the restriction. For example, if a constraint ensures that all values of `qty` > 3, then `sp where @qty = 1` must return an empty result relation.

Project:M36 does not introspect constraints for this type of optimization, but it would be fairly straightforward to implement. There are many forms of this type of optimization, so the implementation would be quite involved to be comprehensive. Project:M36 needs more work in this area.

## 8. CHECK constraints

Project:M36 supports a comprehensive method of constraints called "inclusion dependencies" which encompass every possible database constraint including cross-relation-variable constraints (GLOBAL constraints in SQL parlance). In addition, Project:M36 supports algebraic data types (ADTs) as values, so simulating enumerations with CHECK constraints is obviated (and antiquated).

Translating the film rating example from the sister blog entry, we get:

```
data FilmRating = G | PG | PG_13 | R | NC_17
:showexpr relation{tuple{name "The Smurfs", rating G}}
┌────────────┬──────────────────┐
│name::Text  │rating::FilmRating│
├────────────┼──────────────────┤
│"The Smurfs"│G                 │
└────────────┴──────────────────┘
```

This is an improvement over the SQL's CHECK constraints example because type safety enforced by the ADT guarantees that a `FilmRating` not defined by the data type cannot even be represented, much less optimized, so the error is caught sooner.

## 9. Unneeded Self Join

Unlike in SQL, `x join x` in Project:M36 is unconditionally `x` because Project:M36 does not use three-valued logic. More generally, `x` need not be merely a relation variable's name but could be an entire relational expression. Thus, `join` can be used in lieu of the equality operator for relational expressions and we can safely remove it when both sides of the join are identical.

Furthermore, even when the `join` conditions are not equal but reference the same relation variable, we can collapse the join plus restriction into a single restriction:

```
(x where c1) join (x where c2)
```

is equivalent to:

```
x where c1 and c2
```

Again, the Haskell implementation is completely obvious:

```haskell
case (optExprA, optExprB) of
        (Restrict predA (RelationVariable nameA ()),
         Restrict predB (RelationVariable nameB ())) | nameA == nameB -> pure (Right (Restrict (AndPredicate predA predB) (RelationVariable nameA ())))
        _ -> if optExprA == optExprB then --A join A == A                                         
                         pure (Right optExprA)
                       else
                         pure (Right (Join optExprA optExprB))
```

# 10. Predicate Pushdown

This optimization is a bit more contentious, as the sister blog entry rightfully points out. In a tuple-oriented storage system, slicing tuples horizontally (restriction: `s where name`) is cheaper than slicing vertically (projection: `s{sname}`), so it makes sense to push restriction predicates "down" into projections in order to execute the restriction first.

For example:

```
x{proj} where c1
```

becomes:

```
(x where c1){proj}
```

so that the projection is evaluated potentially on fewer tuples. The pushdown also works on `union`:

```
(x union y) where c
```

becomes:

```
(x where c) union (y where c)
```

so that the union can receive (maybe) fewer tuples.

The implementation is almost trivial:

```
Restrict restrictAttrs (Project projAttrs subexpr) ->
  Project projAttrs (Restrict restrictAttrs (applyStaticRestrictionPushdown subexpr))
```

## Conclusion

This blog post is merely a follow-up to the jooq post and is not meant to be an exhaustive list of Project:M36 static optimizations. Still, this list of optimizations is a fun way of showing how easy it can be to create static optimizations for Project:M36 which throws off the crustiness of SQL (such as three-valued logic) in preference to mathematical coherence (such as set theory). This flies in the face of common database implementations approaches which veer from mathematical correctness in deference to "optimizations". Haskell makes it easy to match optimization forms using algebraic data types while the strong mathematical underpinnings make the optimizations straightforward. We have demonstrated that the same optimization techniques are of greater benefit when the relational algebra is strictly followed.

Project:M36 would benefit from many more static optimizations and other exciting features. If you interested in learning more, please [join us](https://github.com/agentm/project-m36#community)!

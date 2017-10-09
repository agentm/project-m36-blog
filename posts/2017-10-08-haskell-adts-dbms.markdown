---
title: Persisting Haskell ADTs The Relational Way
author: AgentM
---

# Persisting Haskell ADTs The Relational Way

Typical DBMSes suffer from a data type impedance mismatch with Haskell data types. Using such DBMSes in Haskell is especially painful because Haskell has a very powerful typing system which the database promptly discards or "downsamples" due to lack of real type support.

Project:M36 is a DBMS which offers support for algebraic data types (ADTs) as first-class database-side values and support for record types to be marshaled from-and-to database tuples without any loss of type enforcement. Furthermore, database-side ADTs can be manipulated with database-side stored functions written in Haskell. Types can further be preserved with constraints which can also be written in Haskell.

Let's take a closer look at the common [blog post schema example](https://github.com/agentm/project-m36/blob/master/examples/blog.hs) for an example of how these features all fit together.

# Models

Let's start out by defining our model.

```Haskell
data Blog = Blog {
  title :: T.Text,
  entry :: T.Text,
  stamp :: UTCTime,
  category :: Category --note that this type is an algebraic data type
  }
          deriving (Generic, Show) --derive Generic so that Tupleable can use default instances

instance Tupleable Blog

data Comment = Comment {
  blogTitle :: T.Text,
  commentTime :: UTCTime,
  contents :: T.Text
  } deriving (Generic, Show)

instance Tupleable Comment             

data Category = Food | Cats | Photos | Other T.Text
  deriving (Atomable, Eq, Show, NFData, Binary, Generic)
```

Note that the only database-specific requirements are that the record-based models are instances of `Tupleable`, a type which can be derived from `Generic` types to marshal the Haskell values to-and-from database values. No database-specific type decorations (such as specifying SQL types) is needed. The database types are Haskell types with no type-level enforcement lost. Each record becomes a tuple in the database with the Haskell attributes directly mapped to tuple attributes.

The blog's `Category` is an ADT which can be represented as a database value or `Atom`. Because the `Category` derives `Generic`, we can also derive `Atomable`. `Category` values are stored as ADTs in the database- no trickery is involved.

Note that an SQL enumeration would not be able to emulate an ADT directly as a database value. In Project:M36, the ADT is also represented in the database as a value of the same type. The type impedance mismatch is resolved and no database-specific changes to the model are necessary.

Next, let's create our database and add some data.

```Haskell
main :: IO ()                       
main = do
  --connect to the database
  let connInfo = InProcessConnectionInfo NoPersistence emptyNotificationCallback []
  conn <- handleIOError $ connectProjectM36 connInfo

  sessionId <- handleIOError $ createSessionAtHead conn "master"

...

createSchema :: SessionId -> Connection -> IO ()  
createSchema sessionId conn = do
  _ <- handleIOErrors $ mapM (executeDatabaseContextExpr sessionId conn) [
    toAddTypeExpr (Proxy :: Proxy Category),
    toDefineExpr (Proxy :: Proxy Blog) "blog",
    toDefineExpr (Proxy :: Proxy Comment) "comment",
    databaseContextExprForForeignKey "blog_comment" ("comment", ["blogTitle"]) ("blog", ["title"]),
    databaseContextExprForUniqueKey "blog" ["title"]
    ]
  pure ()
```

Here we create an in-memory database (just for testing purposes) and use the `Tupleable` function `toDefineExpr` and `Atomable` function `toAddTypeExpr` to create expressions which we will execute against our database. A foreign key constraint between blogs and comments ensures that each blog can have zero or more comments. Finally, we add a uniqueness constraint on the blogs' titles.

Naturally, if we wanted to store the database on disk or connect to a Project:M36 database server, we could configure that here.

# Controllers and Views

We will use `scotty`, a lightweight web framework to present a user interface to display a list of blog posts and individual blog posts along with their blog-specific comments.

```Haskell
scotty 3000 $ do
  S.get "/" (listBlogs sessionId conn)
  S.get "/blog/:blogid" (showBlogEntry sessionId conn)
  S.post "/comment" (addComment sessionId conn)
```

Next, we set up our action handlers.

```Haskell
listBlogs :: SessionId -> Connection -> ActionM ()
listBlogs sessionId conn = do
  eRel <- liftIO $ executeRelationalExpr sessionId conn (RelationVariable "blog" ())
  case eRel of
    Left err -> render500 (toHtml (show err))
    Right blogRel -> do
      blogs <- liftIO (toList blogRel) >>= mapM (handleWebError . fromTuple) :: ActionM [Blog]
      let sortedBlogs = sortBy (\b1 b2 -> stamp b1 `compare` stamp b2) blogs
      html . renderHtml $ do
        h1 "Blog Posts"
        forM_ sortedBlogs $ \blog -> a ! href (toValue $ "/blog/" <> title blog) $ h2 (toHtml (title blog))
```

First, we list all blog entries by querying the database for the relation variable "blog". Then, we convert from database tuples to our `Blog` values using `Tupleable`'s `fromTuple` function. Then, we sort them by date and insert them into our `blaze-html` template.

```Haskell
showBlogEntry :: SessionId -> Connection -> ActionM ()
showBlogEntry sessionId conn = do
  blogid <- param "blogid"
  --query the database to return the blog entry with a relation-valued attribute of the associated comments
  let blogRestrictionExpr = AttributeEqualityPredicate "title" (NakedAtomExpr (TextAtom blogid))
      extendExpr = AttributeExtendTupleExpr "comments" (RelationAtomExpr commentsRestriction)
      commentsRestriction = Restrict
                           (AttributeEqualityPredicate "blogTitle" (AttributeAtomExpr "title"))
                           (RelationVariable "comment" ())
  eRel <- liftIO $ executeRelationalExpr sessionId conn (Extend extendExpr
                                                         (Restrict
                                                          blogRestrictionExpr
                                                          (RelationVariable "blog" ())))
```

Here, we create a query that might look a little unusual by SQL standards. This is because SQL does not support relation-valued attributes whereas Project:M36 does. In this case, alongside collecting the blog information, we collect all the comments alongside the blog tuple as a nested relation containing a set of all comments for this blog post. With SQL, we would need one query per model or duplicate data with a join whereas we can consolidate our queries into one with Project:M36.

```Haskell
let render = html . renderHtml
    formatStamp = formatTime defaultTimeLocale (iso8601DateFormat (Just "%H:%M:%S"))
case eRel of
  Left err -> render500 (toHtml (show err))
  --handle successful query execution
  Right rel -> case singletonTuple rel of
    Nothing -> do --no results for this blog id
      render (h1 "No such blog post")
      status status404
    Just blogTuple -> case fromTuple blogTuple of --just one blog post found- it's a match!
      Left err -> render500 (toHtml (show err))
      Right blog -> do
        --extract comments for the blog
        commentsAtom <- handleWebError (atomForAttributeName "comments" blogTuple)
        commentsRel <- handleWebError (relationForAtom commentsAtom)
        comments <- liftIO (toList commentsRel) >>= mapM (handleWebError . fromTuple) :: ActionM [Comment]
        let commentsSorted = sortBy (\c1 c2 -> commentTime c1 `compare` commentTime c2) comments
        render $ do
          ...
```

After retrieving all the data we need for the page in one query, we extract the singleton blog post, if available, and then extract the comments from the relation-valued attribute as well as sort them by timestamp. Finally, we render the blog info, comments, and a comment form where users can add new comments (elided for brevity).

Our final action adds a comment submitted from the previously-rendered form.

```Haskell
addComment :: SessionId -> Connection -> ActionM ()            
addComment sessionId conn = do
  blogid <- param "blogid"
  commentText <- param "contents"
  now <- liftIO getCurrentTime

  case toInsertExpr [Comment {blogTitle = blogid,
                              commentTime = now,
                              contents = commentText }] "comment" of
    Left err -> handleWebError (Left err)
    Right insertExpr -> do      
      eRet <- liftIO (withTransaction sessionId conn (executeDatabaseContextExpr sessionId conn insertExpr) (commit sessionId conn))
      case eRet of
        Left err -> handleWebError (Left err)
        Right _ ->
          redirect (TL.fromStrict ("/blog/" <> blogid))
```

We use `Tupleable`'s `toInsertExpr` to create a new `Comment` and insert it into the database. The `withTransaction` line commits our new comment to the database, if no other errors are raised (such as a constraint or type violation). Finally, we redirect to the blog post page where the user will see his comment added.

# Conclusion

Project:M36 offers some unique features for Haskell developers which makes persistence and querying a snap including:

* full algebraic data type support with normal Haskell data types
* easy marshaling between database tuples and Haskell values
* relation-valued attributes
* a mathematically-sound relational model
* an EDSL for relational queries
* database-server-side Haskell (not shown in this example)

If you would like to learn more about Project:M36, please check out our [Hackage docs](http://hackage.haskell.org/package/project-m36) or our [documentation](https://github.com/agentm/project-m36#documentation).

You can also reach us with questions on `irc.freenode.net#project-m36`.

module RealWorld.Conduit.Articles.Database
  ( all
  , create
  , destroy
  , favorite
  , feed
  , find
  , unsafeFind
  , unfavorite
  , update
  , attributesForUpdate
  , attributesForInsert
  ) where

import Control.Lens ((^.), _1, _2, _3, _4, _5, _6, view)
import Control.Monad.Error.Class (MonadError, throwError)
import Control.Monad.Reader.Class (MonadReader, ask)
import Control.Monad.Trans.Control (MonadBaseControl)
import qualified Data.Char as Char
import qualified Data.Map as Map
import Data.Maybe (catMaybes)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Data.Validation (Validation(Failure, Success), validation)
import Data.Vector (Vector)
import qualified Data.Vector as Vector
import Database.Beam.Postgres.Extended
  ( Nullable
  , PgInsertReturning
  , PgQExpr
  , PgSelectSyntax
  , PgUpdateReturning
  , Q
  , (&&.)
  , (<-.)
  , (==.)
  , aggregate_
  , all_
  , array_
  , conflictingFields
  , count_
  , default_
  , delete
  , desc_
  , exists_
  , group_
  , guard_
  , in_
  , insert
  , insertExpressions
  , insertReturning
  , insertValues
  , isSubsetOf_
  , just_
  , leftJoin_
  , limit_
  , offset_
  , onConflict
  , onConflictDefault
  , onConflictDoNothing
  , orderBy_
  , pgArrayAgg
  , pgBoolOr
  , primaryKey
  , references_
  , runDelete
  , runInsert
  , runInsertReturning
  , runSelect
  , runUpdateReturning
  , select
  , updateReturning
  , val_
  )
import Database.PostgreSQL.Simple (Connection)
import Prelude hiding (all, find)
import RealWorld.Conduit.Articles.Article (Article(Article))
import qualified RealWorld.Conduit.Articles.Article as Article
import RealWorld.Conduit.Articles.Article.Attributes (Attributes(..))
import qualified RealWorld.Conduit.Articles.Database.Article as Persisted
import RealWorld.Conduit.Articles.Database.Article (ArticleT)
import RealWorld.Conduit.Articles.Database.ArticleTag (ArticleTagT(ArticleTag))
import qualified RealWorld.Conduit.Articles.Database.ArticleTag as ArticleTag
import qualified RealWorld.Conduit.Articles.Database.Favorite as Favorite
import RealWorld.Conduit.Articles.Database.Favorite (FavoriteT(..))
import RealWorld.Conduit.Database
  ( ConduitDb(..)
  , QueryError(..)
  , conduitDb
  , maybeRow
  , rowList
  , singleRow
  )
import qualified RealWorld.Conduit.Tags.Database as Tag
import RealWorld.Conduit.Tags.Database.Tag (PrimaryKey(unTagId))
import RealWorld.Conduit.Users.Database (selectProfiles)
import qualified RealWorld.Conduit.Users.Database.User as User
import RealWorld.Conduit.Users.Database.User
  ( PrimaryKey(unUserId)
  , User
  , UserId
  , UserT(username)
  )
import RealWorld.Conduit.Users.Profile (Profile(Profile))
import RealWorld.Conduit.Validation (ValidationErrors, requiredText)

insertArticle
  :: UserId -> UTCTime -> Attributes Identity -> PgInsertReturning Persisted.Article
insertArticle authorId currentTime Attributes { title, description, body }
  = insertReturning
    (conduitArticles conduitDb)
    (insertExpressions
      [ Persisted.Article
          { Persisted.id          = default_
          , Persisted.slug        = val_ (generateSlug title)
          , Persisted.title       = val_ title
          , Persisted.description = val_ description
          , Persisted.body        = val_ body
          , Persisted.createdAt   = val_ currentTime
          , Persisted.updatedAt   = val_ currentTime
          , Persisted.author      = val_ authorId
          }
      ]
    )
    onConflictDefault
    (Just id)

create
  :: ( MonadReader Connection m
     , MonadError QueryError m
     , MonadIO m
     , MonadBaseControl IO m
     )
  => UserId
  -> Attributes Identity
  -> m Article
create authorId attributes = do
  conn <- ask
  currentTime <- liftIO getCurrentTime
  inserted <-
    runInsertReturning
      conn
      (insertArticle authorId currentTime attributes)
      singleRow
  replaceTags (primaryKey inserted) (tagList attributes)
  unsafeFind (Just authorId) (Persisted.slug inserted)

find
  :: (MonadReader Connection m, MonadIO m, MonadBaseControl IO m)
  => Maybe UserId
  -> Text
  -> m (Maybe Article)
find currentUserId slug = do
  conn <- ask
  fmap toArticle <$>
    runSelect conn (select (selectArticle currentUserId slug)) maybeRow

unsafeFind
  :: ( MonadReader Connection m
     , MonadError QueryError m
     , MonadIO m
     , MonadBaseControl IO m
     )
  => Maybe UserId
  -> Text
  -> m Article
unsafeFind currentUserId slug = do
  conn <- ask
  toArticle <$>
    runSelect conn (select (selectArticle currentUserId slug)) singleRow

updateArticle
  :: UTCTime -> Text -> Attributes Maybe -> PgUpdateReturning Persisted.Article
updateArticle currentTime currentSlug Attributes { title, description, body }
  = updateReturning
    (conduitArticles conduitDb)
    (\article -> catMaybes
      [ (Persisted.slug article <-.) . val_  . generateSlug <$> title
      , (Persisted.title article <-.) . val_ <$> title
      , (Persisted.description article <-.) . val_ <$> description
      , (Persisted.body article <-.) . val_ <$> body
      , Just (Persisted.updatedAt article <-. val_ currentTime)
      ]
    )
    ((val_ currentSlug ==.) . Persisted.slug)
    id

update
  :: ( MonadReader Connection m
     , MonadError QueryError m
     , MonadIO m
     , MonadBaseControl IO m
     )
  => UserId
  -> Text
  -> Attributes Maybe
  -> m Article
update authorId currentSlug attributes = do
  conn <- ask
  currentTime <- liftIO getCurrentTime
  updated <-
    runUpdateReturning
      conn
      (updateArticle currentTime currentSlug attributes)
      singleRow
  traverse_ (replaceTags (primaryKey updated)) (tagList attributes)
  unsafeFind (Just authorId) (Persisted.slug updated)

assignTags
  :: (MonadReader Connection m, MonadIO m, MonadBaseControl IO m)
  => Persisted.ArticleId
  -> Set Text
  -> m ()
assignTags articleId tags = do
  tagIds <- map primaryKey <$> Tag.create tags
  conn <- ask
  void $
    runInsert conn $
    insert
      (conduitArticleTags conduitDb)
      (insertValues (map (ArticleTag articleId) tagIds))
      (onConflict (conflictingFields id) onConflictDoNothing)

deleteTags
  :: (MonadReader Connection m, MonadIO m)
  => Persisted.ArticleId
  -> m ()
deleteTags articleId = do
  conn <- ask
  void $
    runDelete conn $
    delete
      (conduitArticleTags conduitDb)
      ((val_ articleId ==.) . ArticleTag.article)

replaceTags
  :: (MonadReader Connection m, MonadIO m, MonadBaseControl IO m)
  => Persisted.ArticleId
  -> Set Text
  -> m ()
replaceTags articleId tags =
  deleteTags articleId *> assignTags articleId tags

destroy
  :: (MonadReader Connection m, MonadIO m)
  => Persisted.ArticleId
  -> m ()
destroy articleId = do
  conn <- ask
  void $
    runDelete conn $
    delete (conduitArticles conduitDb) ((val_ articleId ==.) . primaryKey)

favorite
  :: (MonadReader Connection m, MonadIO m)
  => Persisted.ArticleId
  -> UserId
  -> m ()
favorite article user = do
  conn <- ask
  void $
    runInsert
      conn $ insert
      (conduitFavorites conduitDb)
      (insertValues [Favorite article user])
      onConflictDefault

unfavorite
  :: (MonadReader Connection m, MonadIO m)
  => Persisted.ArticleId
  -> UserId
  -> m ()
unfavorite article user = do
  conn <- ask
  void $
    runDelete conn $
    delete (conduitFavorites conduitDb) $ \(Favorite favArticle favUser) ->
      favUser ==. val_ user &&. favArticle ==. val_ article

type ArticleRow s =
  ( ArticleT (PgQExpr s)
  , PgQExpr s (Vector (Maybe Text))
  , PgQExpr s (Maybe Bool)
  , PgQExpr s Integer
  , UserT (PgQExpr s)
  , PgQExpr s (Maybe Bool)
  )

type ArticleResult =
  ( Persisted.Article
  , Vector (Maybe Text)
  , Maybe Bool
  , Integer
  , User
  , Maybe Bool
  )

selectArticles :: Maybe UserId -> Q PgSelectSyntax ConduitDb s (ArticleRow s)
selectArticles currentUserId =
  aggregate_
      (\(article, tag, favorite', author, following) ->
        ( group_ article
        , pgArrayAgg $ unTagId (ArticleTag.tag tag)
        , pgBoolOr
            (maybe
              (val_ False)
              ((Favorite.user favorite' ==.) . just_ . val_)
              currentUserId)
        , count_ $ unUserId (Favorite.user favorite')
        , group_ author
        , group_ following
        )
      )
    $ do
        article <- all_ (conduitArticles conduitDb)
        (author, following) <- selectProfiles currentUserId
        guard_ (Persisted.author article ==. primaryKey author)
        favorite' <- selectFavorites article
        tag      <- selectTags article
        pure
          ( article
          , tag
          , favorite'
          , author
          , following
          )

toArticle :: ArticleResult -> Article
toArticle =
  Article
    <$> (Persisted.id . view _1)
    <*> (Persisted.slug . view _1)
    <*> (Persisted.title . view _1)
    <*> (Persisted.description . view _1)
    <*> (Persisted.body . view _1)
    <*> (Set.fromList . catMaybes . Vector.toList . view _2)
    <*> (Persisted.createdAt . view _1)
    <*> (Persisted.updatedAt . view _1)
    <*> (fromMaybe False . view _3)
    <*> (fromIntegral . view _4)
    <*> (Profile
          <$> (User.id . view _5)
          <*> (User.username . view _5)
          <*> (User.bio . view _5)
          <*> (User.image . view _5)
          <*> fromMaybe False . view _6
          )

selectFilteredArticles
  :: Maybe UserId
  -> Integer
  -> Integer
  -> Set Text
  -> Set Text
  -> Set Text
  -> Q PgSelectSyntax ConduitDb s (ArticleRow s)
selectFilteredArticles currentUserId limit offset usernames tags favorited
  = orderBy_ (desc_ . Persisted.createdAt . view _1)
    $ limit_ limit
    $ offset_ offset
    $ do
        article <- selectArticles currentUserId
        unless (null usernames)
          $ guard_
              $ User.username (article ^. _5)
                  `in_` map val_ (Set.toList usernames)
        for_ (Set.toList tags) $ \tag ->
          guard_
            $ array_ [val_ (Just tag)] `isSubsetOf_` (article ^. _2)
        unless (null favorited) $ do
          favorite' <- selectFavorites (article ^. _1)
          user     <- all_ (conduitUsers conduitDb)
          guard_
            $ (username user `in_` map val_ (Set.toList favorited)) &&.
              (just_ (primaryKey user) ==. Favorite.user favorite')
        pure article

all
  :: (MonadReader Connection m, MonadIO m, MonadBaseControl IO m)
  => Maybe UserId
  -> Integer
  -> Integer
  -> Set Text
  -> Set Text
  -> Set Text
  -> m [Article]
all currentUserId limit offset usernames tags favorited = do
  conn <- ask
  articles <-
    runSelect
      conn
      (select
         (selectFilteredArticles
            currentUserId
            limit
            offset
            usernames
            tags
            favorited))
      rowList
  pure (toArticle <$> articles)

selectFeedArticles
  :: UserId
  -> Integer
  -> Integer
  -> Q PgSelectSyntax ConduitDb s (ArticleRow s)
selectFeedArticles currentUserId limit offset = do
  article <- selectFilteredArticles (Just currentUserId) limit offset mempty mempty mempty
  guard_ $ article ^. _6 ==. val_ (Just True)
  pure article

feed
  :: (MonadReader Connection m, MonadIO m, MonadBaseControl IO m)
  => UserId
  -> Integer
  -> Integer
  -> m [Article]
feed currentUserId limit offset = do
  conn <- ask
  articles <-
    runSelect
      conn
      (select (selectFeedArticles currentUserId limit offset))
      rowList
  pure (toArticle <$> articles)

selectArticle
  :: Maybe UserId
  -> Text
  -> Q PgSelectSyntax ConduitDb s (ArticleRow s)
selectArticle currentUserId slug = do
  article <- selectArticles currentUserId
  guard_ $ Persisted.slug (article ^. _1) ==. val_ slug
  pure article

selectFavorites ::
     ArticleT (PgQExpr s)
  -> Q PgSelectSyntax ConduitDb s (FavoriteT (Nullable (PgQExpr s)))
selectFavorites article =
  leftJoin_
    (all_ (conduitFavorites conduitDb))
    ((`references_` article) . Favorite.article)

selectTags
  :: ArticleT (PgQExpr s)
  -> Q PgSelectSyntax ConduitDb s (ArticleTagT (Nullable (PgQExpr s)))
selectTags article =
  leftJoin_
    (all_ (conduitArticleTags conduitDb))
    ((`references_` article) . ArticleTag.article)

generateSlug :: Text -> Text
generateSlug = Text.intercalate "-" . Text.words . Text.toLower . Text.filter
  ((||) <$> Char.isAlphaNum <*> Char.isSpace)

slugExists
  :: (MonadIO m, MonadReader Connection m, MonadBaseControl IO m)
  => Text
  -> m Bool
slugExists slug = do
  conn <- ask
  fromMaybe False <$> runSelect conn (select query) maybeRow
  where
    query :: Q PgSelectSyntax ConduitDb s (PgQExpr s Bool)
    query = pure $ exists_ $ do
      article <- all_ (conduitArticles conduitDb)
      guard_ (Persisted.slug article ==. val_ slug)
      pure article

titleGeneratingUniqueSlug
  :: (MonadIO m, MonadReader Connection m, MonadBaseControl IO m)
  => Text
  -> Compose m (Validation ValidationErrors) Text
titleGeneratingUniqueSlug title =
  Compose $ do
    taken <- slugExists slug
    pure $
      if taken
        then Failure $
             Map.singleton "title" ["Would produce duplicate slug: " <> slug]
        else Success title
  where
    slug = generateSlug title

makeTitle
  :: (MonadIO m, MonadReader Connection m, MonadBaseControl IO m)
  => Text
  -> Compose m (Validation ValidationErrors) Text
makeTitle title =
  requiredText "title" title *> titleGeneratingUniqueSlug title

attributesForInsert
  :: ( MonadIO m
     , MonadReader Connection m
     , MonadBaseControl IO m
     , MonadError ValidationErrors m
     )
  => Text
  -> Text
  -> Text
  -> Set Text
  -> m (Attributes Identity)
attributesForInsert title description body tags =
  (validation throwError pure =<<) . getCompose $
  Attributes
    <$> makeTitle title
    <*> requiredText "description" description
    <*> requiredText "body" body
    <*> pure tags

makeUpdateTitle
  :: (MonadIO m, MonadReader Connection m, MonadBaseControl IO m)
  => Text
  -> Text
  -> Compose m (Validation ValidationErrors) Text
makeUpdateTitle current title
  | generateSlug title == current = requiredText "title" title
  | otherwise = makeTitle title

attributesForUpdate
  :: ( MonadIO m
     , MonadReader Connection m
     , MonadBaseControl IO m
     , MonadError ValidationErrors m
     )
  => Article
  -> Maybe Text
  -> Maybe Text
  -> Maybe Text
  -> Maybe (Set Text)
  -> m (Attributes Maybe)
attributesForUpdate current title description body tags =
  (validation throwError pure =<<) . getCompose $
  Attributes
    <$> traverse (makeUpdateTitle (Article.slug current)) title
    <*> traverse (requiredText "description") description
    <*> traverse (requiredText "body") body
    <*> pure tags

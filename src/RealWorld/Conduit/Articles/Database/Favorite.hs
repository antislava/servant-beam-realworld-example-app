module RealWorld.Conduit.Articles.Database.Favorite
  ( FavoriteT(..)
  , Favorite
  , PrimaryKey(FavoriteId)
  ) where

import Database.Beam (Beamable, Identity, PrimaryKey, Table(..))
import RealWorld.Conduit.Articles.Database.Article (ArticleT)
import RealWorld.Conduit.Users.Database.User (UserT)

data FavoriteT f = Favorite
  { article :: PrimaryKey ArticleT f
  , user :: PrimaryKey UserT f
  }

deriving instance Generic (FavoriteT f)
deriving instance Beamable FavoriteT

type Favorite = FavoriteT Identity

deriving instance Show Favorite

instance Table FavoriteT where
  data PrimaryKey FavoriteT f
    = FavoriteId
        (PrimaryKey ArticleT f)
        (PrimaryKey UserT f)
  primaryKey = FavoriteId <$> article <*> user

deriving instance Generic (PrimaryKey FavoriteT f)
deriving instance Beamable (PrimaryKey FavoriteT)

type FavoriteId = PrimaryKey FavoriteT Identity

deriving instance Show FavoriteId
deriving instance Eq FavoriteId

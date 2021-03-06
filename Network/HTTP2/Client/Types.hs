module Network.HTTP2.Client.Types where

import Network.HTTP2.Arch

----------------------------------------------------------------

-- | HTTP\/2 client
type Client a = (Request -> (Response -> IO a) -> IO a) -> IO a

-- | Request from client.
newtype Request = Request OutObj

-- | Response from server.
newtype Response = Response InpObj

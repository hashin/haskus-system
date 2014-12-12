{-# LANGUAGE LambdaCase, OverloadedStrings #-}
{-# LANGUAGE NoMonomorphismRestriction #-}

import ViperVM.Platform.Host as V
import ViperVM.Platform.PlatformInfo
import ViperVM.Platform.Loading
import ViperVM.Platform.Config
import ViperVM.Platform.Memory
import ViperVM.Platform.Types
   ( Memory(..)
   , memoryUID
   , networkUID
   , Buffer(..)
   , bufferUID
   )
import qualified ViperVM.STM.TSet as TSet

import Paths_ViperVM
import Data.Version

import Control.Concurrent.STM

import Control.Applicative ((<$>))
import Control.Monad (msum, forM_, guard, mzero)
import Control.Monad.Trans.Class (lift)
import System.Environment
import Text.Printf
import Network.Socket (withSocketsDo)
import Data.Maybe (listToMaybe, isJust)

import Happstack.Server

import Text.Blaze.Html5 ((!), toHtml, docTypeHtml, Html)
import qualified Text.Blaze.Html5.Attributes as A
import qualified Text.Blaze.Html5 as H

main :: IO ()
main = withSocketsDo $ do

   -- Loading platform
   hst <- loadPlatform defaultConfig {
      enableOpenCLCPUs = False
   }

   getArgs >>= \case
      []  -> server (nullConf { port = 8000}) hst
      [p] -> server (nullConf { port = read p}) hst
      _   -> putStrLn =<< (printf "Usage: %s [PORT]" <$> getProgName)


server :: Conf -> V.Host -> IO ()
server conf hst = do
   putStrLn (printf "Starting Web server at localhost:%d" (port conf))
   simpleHTTP conf $ msum
      [ 
      
        -- CSS 
        dir "css" $ dir "style.css" $ do
         cssPath <- lift $ getDataFileName "data/web/css/style.css"
         serveFile (asContentType "text/css") cssPath

        -- Show memory information
      , dir "localhost" $ dir "memory" $ path $ \uid -> showMemory hst uid

        -- Perform memory action
      , dir "localhost" $ dir "memory" $ path $ \uid -> memoryAction hst uid

        -- Show network information
      , dir "localhost" $ dir "network" $ path $ \uid -> showNetwork hst uid

        -- Show platform information
      , dir "localhost" $ showHost hst

        -- Show welcome screen
      , nullDir >> (ok . toResponse . appTemplate hst "Welcome" $ showWelcome)
      ]

-- | Template of all pages
appTemplate :: V.Host -> String -> Html -> Html
appTemplate _ title bdy = docTypeHtml $ do
   H.head $ do
      H.title "ViperVM Web Interface"
      H.meta ! A.httpEquiv "Content-Type"
             ! A.content "text/html;charset=utf-8"
      H.link ! A.rel "stylesheet" 
             ! A.type_ "text/css" 
             ! A.href "/css/style.css"
   H.body $ do
      H.div (toHtml $ "ViperVM " ++ showVersion version ++ " / " ++ title)
         ! A.class_ "headtitle"
      bdy

-- | Welcoming screen
showWelcome :: Html
showWelcome = H.a "Local hst information" ! A.href "/localhost"

-- | Show the host
showHost :: V.Host -> ServerPartT IO Response
showHost hst = do

   (mems,procs,nets) <- lift . atomically $ do
      mems <- TSet.toList =<< hostMemories hst
      procs <- TSet.toList =<< hostProcessors hst
      nets <- TSet.toList =<< hostNetworks hst
      return (mems,procs,nets)

   ok . toResponse . appTemplate hst "Local host" $ do
      H.h2 "Memories"
      H.ul $ forM_ mems $ \mem -> H.li $
         H.a (toHtml $ memoryInfo mem)
            ! A.href (H.toValue $ "/localhost/memory/" ++ show (memoryUID mem))

      H.h2 "Processors"
      H.ul $ forM_ procs $ \p ->
         H.li . toHtml $ procInfo p

      H.h2 "Networks"
      H.ul $ forM_ nets $ \net -> H.li $
         H.a (toHtml $ networkInfo net)
            ! A.href (H.toValue $ "/localhost/network/" ++ show (networkUID net))

-- | Show a memory
showMemory :: V.Host -> String -> ServerPartT IO Response
showMemory hst uid = do
   method GET

   -- check that the memory with the given identifier exists
   mem <- lift . atomically $ findMemoryByUID hst (read uid)
   guard (isJust mem)
   let Just m = mem

   (nbuffers,buffers) <- lift $ atomically $ do
      n <- memoryBufferCount m
      bufs <- TSet.toList $ memoryBuffers m
      return (n,bufs)

   uri <- rqUri <$> askRq
   
   ok . toResponse . appTemplate hst ("Memory - " ++ uid) $ do
      H.h2 (toHtml $ "Memory - " ++ uid)

      H.ul $ do
         H.li $ toHtml (memoryInfo m)
         H.li $ H.form 
            ! A.action (H.toValue uri)
            ! A.enctype "multipart/form-data" 
            ! A.method "POST" $ do 
               H.input ! A.type_ "hidden" ! A.name "action" ! A.value "alloc"
               H.label ! A.for "buffer_alloc_size" $ "Buffer size (in KB) " 
               H.input ! A.type_ "number" ! A.id "buffer_alloc_size" 
                  ! A.name "buffer_alloc_size" ! A.value "1024"
                  ! A.pattern "\\d*"
               H.input ! A.type_ "submit" ! A.value "Allocate buffer"

      H.h2 (toHtml (printf "Buffers (%d)" nbuffers :: String))

      H.ul $ forM_ buffers $ \buf -> do
         let
            sz = bufferSize buf
            sizeMB = fromIntegral sz / (1024.0 * 1024.0) :: Float
         H.li $ do
            toHtml (printf "Buffer - %f MB" sizeMB :: String)
            H.preEscapedToMarkup ("&nbsp;" :: String)
            H.form 
               ! A.action (H.toValue uri)
               ! A.class_ "buffer_release_form"
               ! A.enctype "multipart/form-data" 
               ! A.method "POST" $ do 
                  H.input ! A.type_ "hidden" ! A.name "action" ! A.value "release"
                  H.input ! A.type_ "hidden" ! A.name "buid" ! A.value (H.toValue (show $ bufferUID buf))
                  H.input ! A.type_ "submit" ! A.value "Release"



-- | Perform a memory action
memoryAction :: V.Host -> String -> ServerPartT IO Response
memoryAction hst uid = do
   method POST

   -- check that the memory with the given identifier exists
   mem <- lift $ atomically $ findMemoryByUID hst (read uid)
   guard (isJust mem)
   let Just m = mem

   decodeBody (defaultBodyPolicy "/tmp/" 4096 4096 4096)
   action <- lookRead "action"

   case (action :: String) of
      "alloc" -> do
         bsize <- lookRead "buffer_alloc_size"
         res <- lift $ memoryBufferAllocate bsize m
         case res of
            Left err -> 
               ok . toResponse . appTemplate hst ("Memory - " ++ uid) $ do
                  H.p (toHtml $ "Cannot allocate buffer of size" ++ show bsize ++ " KB")
                  H.p (toHtml $ "Error: " ++ show err)

            Right _ ->
               ok . toResponse . appTemplate hst ("Memory - " ++ uid) $
                  H.p (toHtml $ "Buffer (" ++ show bsize ++ " KB) successfully allocated")

      "release" -> do
         buid <- read <$> lookRead "buid"
         buf <- lift $ atomically $ do
            bufs <- TSet.toList (memoryBuffers m)
            return $ listToMaybe [b | b <- bufs, bufferUID b == buid]
         
         guard (isJust buf)
         let Just b = buf

         lift $ memoryBufferRelease b
         ok . toResponse . appTemplate hst ("Memory - " ++ uid) $
            H.p "Buffer released"

      _ -> mzero

-- | Show a network
showNetwork :: V.Host -> String -> ServerPartT IO Response
showNetwork hst uid = do
   method GET

   -- check that the memory with the given identifier exists
   -- mem <- lift $ atomically (findMemoryByUID hst (read uid))
   -- guard (isJust mem)
   -- let Just m = mem

   ok . toResponse . appTemplate hst ("Network - " ++ uid) $
      H.h2 (toHtml $ "Network - " ++ uid)

      -- H.ul $ do
      --    H.li $ toHtml (networkInfo m)

import Control.Concurrent (forkIO)
import Control.Concurrent.STM (STM, TVar, atomically, check, newTVar, orElse, readTVar, retry, writeTVar)

{- 1. Modelar usando variables transaccionales un buffer de capacidad 1 que provee las operaciones put y
get. Se utilizar´an variables de tipo TVar (Maybe t) para representar buffers con valores de tipo t.
a) Definir las operaciones de manera tal que las mismas sean no bloqueantes, es decir, tienen el tipo:
get :: TVar (Maybe t) -> STM (Maybe t)
put :: TVar (Maybe t) -> t -> STM Bool
b) Dar un programa que crea un buffer con valor inicial 0 y luego ejecute concurrentemente una
operaci´on de escritura del valor 1 y una de lectura. El programa debe mostrar por pantalla el
resultado que se obtiene de la lectura del buffer.
c) Dar una implementaci´on de buffer donde las dos operaciones son bloqueantes, es decir, se debe
esperar a que est´e vac´ıo para escribir y lleno para leer. Se espera que las operaciones tengan el
siguiente tipo
get :: TVar (Maybe b) -> STM b
put :: TVar (Maybe t) -> t -> STM ()
d) Definir una una operaci´on read que permite leer (sin tomar) el contenido del buffer . Si el buffer
est´a vac´ıo, la operaci´on se bloquea hasta tanto se agregue alg´un valor. -}

get :: TVar (Maybe t) -> STM (Maybe t)
get var = do
  val <- readTVar var
  writeTVar var Nothing
  return val

put :: TVar (Maybe t) -> t -> STM Bool
put var val = do
  oldVal <- readTVar var
  case oldVal of
    Just _ -> return False
    Nothing -> do
      writeTVar var (Just val)
      return True

writer b = do
  atomically (put b 1)
  return ()

reader b = do
  v <- atomically (get b)
  putStrLn $ "Consumo " ++ show v

mainBuffer = do
  b <- atomically (newTVar (Just 0))
  forkIO (writer b)
  forkIO (reader b)
  return ()

getB :: TVar (Maybe b) -> STM b
getB b = do
  xs <- readTVar b
  case xs of
    Nothing -> retry
    Just val -> do
      writeTVar b Nothing
      return val

putB :: TVar (Maybe t) -> t -> STM ()
putB var val = do
  oldVal <- readTVar var
  case oldVal of
    Just _ -> retry
    Nothing -> do
      writeTVar var (Just val)

peek :: TVar (Maybe b) -> STM b
peek b = do
  xs <- readTVar b
  maybe retry return xs

{- 2. Implementar un sem´aforo en t´erminos de STM. Mostrar un fragmento de c´odigo en el cual un cliente
toma at´omicamente dos permisos. -}

type Sem = TVar Int

wait :: Sem -> IO ()
wait s =
  atomically
    ( do
        v <- readTVar s
        check (v > 0)
        writeTVar s (v - 1)
    )

signal :: Sem -> IO ()
signal s =
  atomically
    ( do
        v <- readTVar s
        writeTVar s (v + 1)
    )

{- 3. Se desea administrar la asignaci´on de recursos, donde se debe mantener una cola de recursos de un
determinado tipo y permite que se tomen y liberen a trav´es de dos operaciones tomar (que devuelve el
primer elemento de la cola) y liberar (que agrega a la cola el elemento que se libera).
a) Dar una implementaci´on utilizando STM.
b) Mostrar como un proceso pueda tomar y liberar una cantidad arbitraria de recursos al mismo
tiempo -}

type Queue a = TVar [a]

liberar :: Queue a -> a -> STM ()
liberar q x = do
  xs <- readTVar q
  writeTVar q (xs ++ [x])

tomar :: Queue a -> STM a
tomar q = do
  xs <- readTVar q
  case xs of
    [] -> retry
    (x : xs) -> do
      writeTVar q xs
      return x

liberarN :: Queue a -> [a] -> STM ()
liberarN q recs = wloop (length recs)
  where
    wloop 0 = return ()
    wloop n = do
      liberar q (recs !! (n - 1))
      wloop (n - 1)

tomarN :: Queue a -> Int -> STM [a]
tomarN q 0 = return []
tomarN q n = do
  x <- tomar q
  xs <- tomarN q (n - 1)
  return (x : xs)

{- 4. Considerar el juego de las bolitas, donde existen dos tipos de participantes: los generadores y los
consumidores de bolitas. Los generadores crean bolitas de a una a la vez y las colocan en una bolsa
(suman un punto por cada bolita que logran colocar en la bolsa). Los consumidores toman pares de
bolitas y suman un punto por cada par (pero no pueden tomar mas de un par por vez). No se conoce
a priori la cantidad de participantes que est´an jugando, pero se debe garantizar en todo momento que
la bolsa no contenga mas bolitas que la cantidad de generadores que se encuentran jugando -}

mainBolitas = do
  bolsa <- atomically (newTVar [])
  waitForConsume <- atomically (newTVar 0)
  waitForProduce <- atomically (newTVar 0)
  bolsaMutex <- atomically (newTVar 0)
  forkIO (consumidor waitForProduce bolsaMutex waitForConsume bolsa {- cantidad arbitraria de forks -})
  forkIO (productor waitForProduce bolsaMutex waitForConsume bolsa {- cantidad arbitraria de forks -})

consumidor :: Sem -> Sem -> Sem -> TVar [()] -> IO ()
consumidor waitForProduce bolsaMutex waitForConsume bolsa = cloop
  where
    cloop = do
      wait waitForProduce
      wait waitForProduce
      wait bolsaMutex
      atomically
        ( do
            xs <- readTVar bolsa
            writeTVar bolsa (drop 2 xs)
        )
      signal bolsaMutex
      signal waitForConsume
      signal waitForConsume

productor :: Sem -> Sem -> Sem -> TVar [()] -> IO ()
productor waitForProduce bolsaMutex waitForConsume bolsa = cloop
  where
    cloop = do
      wait bolsaMutex
      atomically
        ( do
            xs <- readTVar bolsa
            writeTVar bolsa (() : xs)
        )
      signal bolsaMutex
      signal waitForProduce
      wait waitForConsume

{- 5. Dar una soluci´on al problema de los fumadores. En el mismo hay tres procesos fumadores y un proceso
proveedor. Cada uno de los procesos fumadores har´a un cigarrillo y lo fumar´a. Para hacer un cigarrillo
requiere tabaco, papel y f´osforos. Cada proceso fumador tiene uno de los tres elementos. Es decir,
un proceso tiene tabaco, otro tiene papel y el tercero tiene f´osforos. El proveedor tiene disponibilidad
no acotada de cualquiera de los elementos. Peri´odicamente coloca dos elementos sobre la mesa, y el
fumador que tiene el tercer elemento los toma y fuma su cigarrillo -}

{- hay una mesa por aca fumador? una mesa en total y los fumadores comiten por los elementos que les falta?
    de ser asi se me ocurre hacer un proceso que tome como parametro dos buffers de capacidad 1 (ejercicio 1)
    que almacenen para cada proceso los dos recursos que NO tiene

    cada fumador intentara constantemente adquirir esos dos recursos y cuando obtiene los dos ya puede armar un puchardo

    mientras, el proveedor intentara constantemente hacer put sobre dos recursos random

    asi entiendo yo que se debe modelar, pero no me queda claro
 -}

{- 6. Dar una soluci´on al problema de los fil´osofos comensales.
Ayuda: Puede modelar los tenedores como buffers (usando la resoluci´on del ejercicio 1.b). -}

{- 7. Considerar el problema de la pizzer´ıa. En el bar X se fabrican dos tipos de pizzas: las chicas y las
grandes. El maestro pizzero va colocando de a una las pizzas listas en una barra para que los clientes se
sirvan y pasen luego por la caja. Lamentablemente todos los clientes tienen buen apetito y se comportan
de la siguiente manera: prefieren siempre tomar un pizza grande, pero si no lo logran se conforman con
dos peque˜nas. Los clientes son mal educados y no esperan en una cola (todos compiten por las pizzas).
Dar una soluci´on utilizando STM en donde cada cliente y el maestro pizzero son modelados como
threads -}

{- aca usaria un orElse para que cuando no pueda obtener la pizza grande, intente obtener dos chicas
    la barra es una cola no acotada?
 -}

cliente :: Stack () -> Stack () -> STM ()
cliente barraGrandes barraChicas =
  orElse
    ( do
        pop barraGrandes
    )
    ( do
        pop barraChicas
        pop barraChicas
    )

{- y para en pizzero un while true (recursivamente i guess) creando de forma random una grande o chica -}

{- 8. Implementar un tipo de datos Pila concurrente que permite la ejecuci´on de las operaciones push y pop. -}
type Stack a = TVar [a]

push :: Stack a -> a -> STM ()
push b x = do
  xs <- readTVar b
  writeTVar b (x : xs)

pop :: Stack a -> STM a
pop b = do
  xs <- readTVar b
  case xs of
    [] -> retry
    (x : xs) -> do
      writeTVar b xs
      return x

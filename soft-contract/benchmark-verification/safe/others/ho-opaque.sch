(module db1 racket
  (provide/contract
   [db1 ([(=/c 0) . -> . (=/c 0)] . -> . [(=/c 0) . -> . (=/c 0)])])
  (define (db1 f)
    (λ (x) (f (f x)))))

(module f racket
  (provide/contract 
   [f ((=/c 0) . -> . number?)]))

(require 'db1 'f)
((db1 f) •)
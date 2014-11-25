(module subst*
  (provide
   [subst* (any/c any/c any/c . -> . any/c)])
  (define (subst* new old t)
    (cond
      [(equal? old t) new]
      [(cons? t) (cons (subst* new old (car t))
                       (subst* new old (cdr t)))]
      [else t])))

(require subst*)
(subst* • • •)

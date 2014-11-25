(module filter
  (provide
   [filter ((any/c . -> . any/c) (listof any/c) . -> . (listof any/c))])
  (define (filter p? xs)
    (cond
      [(empty? xs) empty]
      [else (let ([x (car xs)]
                  [zs (filter p? (cdr xs))])
              (if (p? x) (cons x zs) zs))])))

(require filter)
(filter • •)

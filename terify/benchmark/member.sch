(module member
  (provide
   [member (any/c (listof any/c) . -> . #|HERE|# boolean?)])
  (define (member x l)
    (cond
     [(empty? l) empty]
     [(equal? x (car l)) l]
     [else (member x (cdr l))])))

(require member)
(member • •)

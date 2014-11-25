(module f (provide [f (integer? (integer? . -> . any/c) . -> . any/c)])
  (define (f x g) (g (+ x 1))))
(module h
  (provide
   [h (->i ([z integer?])
	   (res (z) ((and/c integer? (>/c z)) . -> . any/c)))])
  (define (h z) (λ (y) 'unit)))
(module main (provide [main (integer? . -> . any/c)])
  (require f h)
  (define (main n)
    (if (>= n 0) (f n (h n)) 'unit)))

(require main)
(main •)

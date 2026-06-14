;; Fennel data filtering example

(local people [{:name "Alice"   :age 30 :role "developer"}
               {:name "Bob"     :age 17 :role "student"}
               {:name "Charlie" :age 25 :role "developer"}
               {:name "Diana"   :age 35 :role "manager"}
               {:name "Eve"     :age 16 :role "student"}])

;; Filter adults using icollect (table comprehension)
(local adults
  (icollect [_ p (ipairs people)]
    (if (>= p.age 18) p.name)))

;; Filter by role using match (pattern matching)
(local developers
  (icollect [_ p (ipairs people)]
    (match (. p :role)
      "developer" (. p :name))))

(print (.. "Adults:     " (table.concat adults ", ")))
(print (.. "Developers: " (table.concat developers ", ")))

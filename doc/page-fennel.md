# Using Fennel with ComEXE

* [Introduction](#introduction)
* [Preparation](#preparation)
* [Writing Fennel code](#writing-fennel-code)
* [Compiling Fennel](#compiling-fennel)
* [Testing](#testing)
* [Compiling as a standalone binary](#compiling-as-a-standalone-binary)
* [Full listing](#full-listing)

# Introduction

ComEXE embeds the [Fennel](https://fennel-lang.org/) compiler. Fennel is a Lisp dialect that compiles to Lua. The compile command translates `.fnl` files to `.lua`.

**[test-fennel.fnl](../tests/examples/fennel/test-fennel.fnl)** → `lua55ce -x --compile` → **[test-fennel.lua](../tests/examples/fennel/test-fennel.lua)** (generated)

# Preparation

Download the [latest ComEXE binaries](https://github.com/pascalcombier/comexe/releases). Project structure:

```
fennel-example\lua55ce-x86_64-windows.exe
fennel-example\lua55ce-x86_64-linux
fennel-example\src\test-fennel.fnl
```

# Writing Fennel code

Create a file named `test-fennel.fnl`:

```fennel
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
```

# Compiling Fennel

Compile the Fennel source to Lua:

```
> lua55ce-x86_64-windows.exe -x --compile src\test-fennel.fnl
src\test-fennel.fnl -> src\test-fennel.lua
```

The generated Lua code is larger than the initial Fennel code.

# Testing

Run the generated Lua script:

```
> lua55ce-x86_64-windows.exe src\test-fennel.lua
Adults:     Alice, Charlie, Diana
Developers: Alice, Charlie
```

# Compiling as a standalone binary

From the command line:

```
> lua55ce-x86_64-windows.exe -x --make src\test-fennel.lua
```

Run it:

```
> test-fennel.exe
Adults:     Alice, Charlie, Diana
Developers: Alice, Charlie
```

# Full listing

* **[test-fennel.fnl](../tests/examples/fennel/test-fennel.fnl)**
* **[test-fennel.lua](../tests/examples/fennel/test-fennel.lua)** (generated)

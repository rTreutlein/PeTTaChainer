!(import! &self ../chainer_utils)

!(test
   (collapse
      (let $x (Cyclic $x)
         (chainer-add-atom &tmp (Stored $x))))
   ())

!(test
   (collapse
      (chainer-add-atom &tmp (Stored acyclic)))
   (true))

"""Check emitted demo encodings against instructions from the provided test.s."""
import unittest
from assemble import assemble,BASE

class EncodingTests(unittest.TestCase):
    def one(self,text,expected):
        words,_=assemble(text)
        self.assertEqual(words[0],expected)
    def test_addi_negative(self): self.one('addi.w $r12,$r0,-1',0x02bffc0c)
    def test_lu12i(self): self.one('lu12i.w $r12,0x1d0',0x14003a0c)
    def test_ori(self): self.one('ori $r12,$r0,1',0x0380040c)
    def test_load(self): self.one('ld.w $r13,$r13,0',0x288001ad)
    def test_store(self): self.one('st.w $r25,$r12,0',0x29800199)
    def test_csrrd(self): self.one('csrrd $r12,6',0x0400180c)
    def test_csrwr(self): self.one('csrwr $r12,5',0x0400142c)
    def test_csrxchg(self): self.one('csrxchg $r12,$r13,0',0x040001ac)
    def test_srli(self): self.one('srli.w $r12,$r12,16',0x0044c18c)
    def test_jirl(self): self.one('jirl $r0,$r1,0',0x4c000020)
    def test_div(self): self.one('div.w $r19,$r13,$r16',0x002041b3)
    def test_backward_branch(self):
        words,_=assemble('loop: nop\nb loop')
        self.assertEqual(words[1],0x53ffffff)
    def test_forward_conditional(self):
        words,_=assemble('beq $r13,$r12,target\nnop\ntarget: nop')
        self.assertEqual(words[0],0x580009ac)
    def test_labels_after_li(self):
        words,names=assemble('li $r12,0x1faff100\nnext: b next')
        self.assertEqual(names['next'],BASE+8)
        self.assertEqual(words[0],0x143f5fec)
        self.assertEqual(words[1],0x0384018c)
    def test_range_rejected(self):
        with self.assertRaises(ValueError): assemble('addi.w $r1,$r0,2048')
    def test_unaligned_rejected(self):
        with self.assertRaises(ValueError): assemble('b 0x1c000001')

if __name__=='__main__': unittest.main()

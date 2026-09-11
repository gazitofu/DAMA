# -*- coding: utf-8 -*-
import unittest
from qwen_worker import map_alignment, chunk_ranges

class MappingTests(unittest.TestCase):
    def test_symbols_and_repeated_words_preserved(self):
        text='H&Q 15.38% 네 네.'
        items=[{'text':w,'start_time':i*.2,'end_time':(i+1)*.2} for i,w in enumerate(['HQ','1538','네','네'])]
        out=map_alignment(text,items,60_000_000,1_000_000)
        self.assertEqual(''.join(x['text'] for x in out),text)
        self.assertEqual(out[0]['startUs'],60_000_000)
        self.assertEqual(out[-1]['endUs'],60_800_000)
        self.assertEqual(len(out),4)
    def test_mismatch_keeps_entire_text_without_guessed_time(self):
        out=map_alignment('천억 원',[{'text':'천원','start_time':0,'end_time':1}],0,1_000_000)
        self.assertEqual(out[0]['text'],'천억 원'); self.assertIsNone(out[0]['startUs'])
    def test_invalid_and_backward_times(self):
        items=[{'text':'네','start_time':.5,'end_time':.6},
               {'text':'네','start_time':.2,'end_time':.3}]
        out=map_alignment('네 네',items,0,1_000_000)
        self.assertIsNone(out[1]['startUs'])
        for a,b in [(0,0),(-.1,.2),(0,1.001),(float('nan'),1)]:
            self.assertIsNone(map_alignment('네',[{'text':'네','start_time':a,'end_time':b}],0,1_000_000)[0]['startUs'])
    def test_no_frame_loss(self):
        import numpy as np
        samples=np.zeros(301*16000,dtype=np.float32)
        spans=chunk_ranges(samples,16000)
        self.assertEqual(spans[0][0],0); self.assertEqual(spans[-1][1],len(samples))
        self.assertEqual(sum(b-a for a,b in spans),len(samples))
        self.assertTrue(all(spans[i][1]==spans[i+1][0] for i in range(len(spans)-1)))
        self.assertTrue(all(60*16000<=b-a<=120*16000 for a,b in spans[:-1]))

if __name__=='__main__': unittest.main()

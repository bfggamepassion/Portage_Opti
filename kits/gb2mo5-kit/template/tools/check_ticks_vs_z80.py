"""Rejoue une partie dans le MO5 simulé et compare chaque pas de jeu à la
version Z80 (Coleco) partie du même état. À lancer depuis la racine du dépôt
Tennis : python MO5/tools/check_ticks_vs_z80.py
"""
import sys, importlib.util
sys.path.insert(0,'Coleco/tools'); sys.path.insert(0,'MO5/tools')
import cvsim, mo5sim
def cfgload(p):
    spec=importlib.util.spec_from_file_location('c'+str(abs(hash(p))),p); c=importlib.util.module_from_spec(spec); spec.loader.exec_module(c); return c
cc=cfgload('Coleco/port_config.py'); mc=cfgload('MO5/port_config.py')
GB=list(range(0xC000,0xC100))+[0xDD00]+list(range(0xFF80,0xFFFF))
cv=cvsim.Coleco('Coleco/build/Coleco Tennis.rom'); zs=cvsim.symbols()
def z80call(addr):
    m=cv.mem; r=cv.r; sp=0x73F0; m[sp],m[sp+1]=0,1; r[12]=sp; r[26]=0; cv.sim.run(addr,0x100)
mo=mo5sim.MO5(); ms=mo5sim.symbols(); cpu=mo.cpu
keys=mo5sim.parse_keys("60:S 64: 300:S 304: 330:S 334:")
tick=ms['gb_tick']; n=0; prevpcs=[]
while mo.frame<420:
    if cpu.pc==tick:
        before={a:cpu.mem[mc.RAM_MAP(a)] for a in GB}
        ret_sp=cpu.s
        # run MO5 tick until return
        retaddr=(cpu.mem[cpu.s]<<8)|cpu.mem[cpu.s+1]
        while not (cpu.pc==retaddr and cpu.s==ret_sp+2): cpu.step()
        for a,v in before.items(): cv.mem[cc.RAM_MAP(a)]=v
        z80call(zs['gb_tick'])
        d=[a for a in GB if cv.mem[cc.RAM_MAP(a)]!=cpu.mem[mc.RAM_MAP(a)] and a!=0xFFA4]
        n+=1
        if d:
            print('tick',n,'frame',mo.frame,'pad',hex(before[0xFF9A]),hex(before[0xFF9B]),'diff',[hex(a) for a in d[:10]])
            print(' Z80',[hex(cv.mem[cc.RAM_MAP(a)]) for a in d[:10]]); print(' MO5',[hex(cpu.mem[mc.RAM_MAP(a)]) for a in d[:10]])
            break
        continue
    cpu.step()
    if cpu.cycles>=mo.next_frame:
        mo.next_frame+=mo5sim.FRAME; mo.frame+=1; mo.keys=keys(mo.frame)
print('ticks',n)

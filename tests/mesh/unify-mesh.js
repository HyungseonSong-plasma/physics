/* Reproduce: node conform-maxwell.js parent.msh original-maxwell.msh candidate.msh */
const fs = require('node:fs');
function conform(parentText,childText){
 const common=new Set(['plasma','cover','wafer','focus_ring','vacuum','coil1','coil2','coil3']); const shared=t=>common.has(t.g);
 const EPS=1e-10, A=1e-16, key=(a,b)=>a<b?`${a},${b}`:`${b},${a}`;
 function parse(s){const a=s.trim().split(/\r?\n/),sec=n=>a.slice(a.indexOf("$"+n)+1,a.indexOf("$End"+n));const names=Object.fromEntries(sec("PhysicalNames").slice(1).map(l=>{let [d,id,...n]=l.trim().split(/\s+/);return [d+":"+id,n.join(" ").replaceAll('"','')]}));const nodes=new Map(),cls=new Map(),tris=[],entities=new Map();if(sec("MeshFormat")[0].startsWith("2.")){for(const l of sec("Nodes").slice(1)){let [i,...p]=l.trim().split(/\s+/).map(Number);nodes.set(i,p)}for(const l of sec("Elements").slice(1)){let v=l.trim().split(/\s+/).map(Number);if(v[1]===2)tris.push({g:names["2:"+v[3]],n:v.slice(3+v[2]),tag:v[4]})}}else{const en=sec("Entities");let off=1;for(let d=0;d<4;d++)for(let j=0;j<+en[0].trim().split(/\s+/)[d];j++){let v=en[off++].trim().split(/\s+/).map(Number),k=d===0?4:7;entities.set(d+":"+v[0],{v,physical:v.slice(k+1,k+1+v[k])})}let n=sec("Nodes"),i=1;while(i<n.length){let [d,t,p,c]=n[i++].trim().split(/\s+/).map(Number);if(p)throw Error("Parametric nodes unsupported");let ids=n.slice(i,i+c).map(Number);i+=c;for(let id of ids){nodes.set(id,n[i++].trim().split(/\s+/).map(Number));cls.set(id,[d,t])}}let e=sec("Elements");i=1;while(i<e.length){let [d,t,k,c]=e[i++].trim().split(/\s+/).map(Number);for(let j=0;j<c;j++){let v=e[i++].trim().split(/\s+/).map(Number);if(d!==2||k!==2)throw Error("Non-tri child");tris.push({g:names["2:"+entities.get("2:"+t).physical[0]],n:v.slice(1),tag:t})}}}return {nodes,cls,tris,entities,sec}}
 const p=parse(parentText),c=parse(childText), orig=c.tris, nodes=new Map(c.nodes),cls=new Map(c.cls),dist=(a,b)=>Math.hypot(a[0]-b[0],a[1]-b[1]),cross=(a,b,c)=>(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]),on=(q,a,b)=>Math.abs(cross(a,b,q))<=EPS*dist(a,b)&&(q[0]-a[0])*(q[0]-b[0])+(q[1]-a[1])*(q[1]-b[1])<=EPS*EPS;
 function emap(ts){const m=new Map();for(const t of ts)for(let i=0;i<3;i++){let a=t.n[i],b=t.n[(i+1)%3],k=key(a,b);if(!m.has(k))m.set(k,{a,b,ts:[]});m.get(k).ts.push(t)}return m}
 const boundary=m=>[...emap(m.tris).values()].filter(e=>e.ts.some(t=>shared(t))&&(e.ts.length===1||e.ts.some(t=>!shared(t))));
 const pb=boundary(p),cb=boundary(c),pv=[...new Set(pb.flatMap(e=>[e.a,e.b]))],cv=[...new Set(cb.flatMap(e=>[e.a,e.b]))],pt=p.tris.filter(t=>shared(t)),pids=[...new Set(pt.flatMap(t=>t.n))],tagsByGroup=new Map(orig.map(t=>[t.g,t.tag]));
 if(cv.some(i=>!pb.some(e=>on(c.nodes.get(i),p.nodes.get(e.a),p.nodes.get(e.b))))||pv.some(i=>!cb.some(e=>on(p.nodes.get(i),c.nodes.get(e.a),c.nodes.get(e.b)))))throw Error("Incompatible interface geometry");
 const match=new Map(),used=new Set();for(let i of pv){const j=cv.find(j=>dist(p.nodes.get(i),c.nodes.get(j))<EPS);if(j!==undefined){match.set(i,j);used.add(j)}}
 let ext=orig.filter(t=>!shared(t)), removed=0, inserted=0;
 function ccw(n){let a=cross(...n.map(i=>nodes.get(i)));if(Math.abs(a)<=A)throw Error("Degenerate triangle "+n);return a>0?n:[n[0],n[2],n[1]]}
 function triangulate(poly,tag,g){let signed=0;for(let i=0;i<poly.length;i++){let a=nodes.get(poly[i]),b=nodes.get(poly[(i+1)%poly.length]);signed+=a[0]*b[1]-a[1]*b[0]}if(signed<0)poly.reverse();const out=[];while(poly.length>3){let found=false;for(let i=0;i<poly.length;i++){let a=poly[(i+poly.length-1)%poly.length],b=poly[i],d=poly[(i+1)%poly.length],q=nodes.get(a),r=nodes.get(b),s=nodes.get(d);if(cross(q,r,s)<=A)continue;let inside=poly.some(j=>j!==a&&j!==b&&j!==d&&cross(q,r,nodes.get(j))>=-A&&cross(r,s,nodes.get(j))>=-A&&cross(s,q,nodes.get(j))>=-A);if(inside)continue;out.push({g,tag,n:[a,b,d]});poly.splice(i,1);found=true;break}if(!found)throw Error("Ear clipping stuck "+poly)}out.push({g,tag,n:ccw(poly)});return out}
 // Remove each obsolete interface vertex by retriangulating only its external one-ring.
 for(let v of cv){if(used.has(v))continue;const star=ext.filter(t=>t.n.includes(v));if(!star.length)continue;const tags=[...new Set(star.map(t=>t.tag))];if(tags.length!==1)throw Error("Missing mandatory interface junction "+v);const adj=new Map();for(let t of star){let [a,b]=t.n.filter(i=>i!==v);if(!adj.has(a))adj.set(a,[]);if(!adj.has(b))adj.set(b,[]);adj.get(a).push(b);adj.get(b).push(a)}const ends=[...adj].filter(([i,j])=>j.length===1).map(([i])=>i);if(ends.length!==2||[...adj.values()].some(x=>x.length>2))throw Error("Non-chain star "+v);if(!on(nodes.get(v),nodes.get(ends[0]),nodes.get(ends[1])))throw Error("Removal changes geometry "+v);let chain=[ends[0]],prev=null;while(chain.at(-1)!==ends[1]){let cur=chain.at(-1),next=adj.get(cur).find(i=>i!==prev);if(next===undefined||chain.includes(next))throw Error("Invalid chain");chain.push(next);prev=cur}if(chain.length!==adj.size)throw Error("Disconnected star");const del=new Set(star);ext=ext.filter(t=>!del.has(t));ext.push(...triangulate(chain,tags[0],star[0].g));removed++}
 // Classify new interface points on the original straight CAD curves.
 function classify(q){const hits=[];for(let [k,e] of c.entities){if(!k.startsWith("1:"))continue;let v=e.v,i=8+v[7],n=v[i];if(n!==2)continue;let a=c.entities.get("0:"+Math.abs(v[i+1]))?.v,b=c.entities.get("0:"+Math.abs(v[i+2]))?.v;if(a&&b&&on(q,a.slice(1,4),b.slice(1,4)))hits.push(v[0])}if(hits.length!==1)throw Error("Ambiguous CAD curve for "+q+" "+hits);return [1,hits[0]]}
 let next=Math.max(...nodes.keys())+1;const map=new Map();for(let i of pids){if(match.has(i)){let j=match.get(i);map.set(i,j);nodes.set(j,p.nodes.get(i));}else{let j=next++;map.set(i,j);nodes.set(j,p.nodes.get(i));cls.set(j,[2,0])}}
 // Split each external interface edge at the exact Parent boundary vertices.
 const newBoundary=pv.map(i=>map.get(i)), oldInterface=cb.filter(e=>e.ts.some(t=>!shared(t)));
 const boundaryExt=[...emap(ext).values()].filter(e=>e.ts.length===1&&oldInterface.some(o=>on(nodes.get(e.a),c.nodes.get(o.a),c.nodes.get(o.b))&&on(nodes.get(e.b),c.nodes.get(o.a),c.nodes.get(o.b)))||e.ts.length===1&&oldInterface.some(o=>on([(nodes.get(e.a)[0]+nodes.get(e.b)[0])/2,(nodes.get(e.a)[1]+nodes.get(e.b)[1])/2],c.nodes.get(o.a),c.nodes.get(o.b)))&&newBoundary.some(i=>dist(nodes.get(i),nodes.get(e.a))<EPS)&&newBoundary.some(i=>dist(nodes.get(i),nodes.get(e.b))<EPS));
 for(let e of boundaryExt){let a=nodes.get(e.a),b=nodes.get(e.b),points=newBoundary.filter(i=>i!==e.a&&i!==e.b&&on(nodes.get(i),a,b)).sort((i,j)=>dist(a,nodes.get(i))-dist(a,nodes.get(j)));if(!points.length)continue;let t=ext.find(t=>t.n.includes(e.a)&&t.n.includes(e.b));if(!t)throw Error("Lost interface edge");let opposite=t.n.find(i=>i!==e.a&&i!==e.b),seq=[e.a,...points,e.b];ext=ext.filter(x=>x!==t);for(let i=0;i<seq.length-1;i++)ext.push({g:t.g,tag:t.tag,n:ccw([seq[i],seq[i+1],opposite])});inserted+=points.length}

 // Improve low-quality exterior triangles by constrained edge flips. Only
 // flip within the same CAD surface; never modify a plasma/interface edge.
 const qtri=n=>{let [a,b,c]=n.map(i=>nodes.get(i));return 2*Math.sqrt(3)*Math.abs(cross(a,b,c))/(dist(a,b)**2+dist(b,c)**2+dist(c,a)**2)};
 let flips=0;
 for(let sweep=0;sweep<80;sweep++){let count=0;const m=emap(ext), live=new Set(ext);
  for(let e of m.values()){if(e.ts.length!==2)continue;let [t,u]=e.ts;if(t.tag!==u.tag||!live.has(t)||!live.has(u))continue;
   let a=e.a,b=e.b,i=t.n.find(x=>x!==a&&x!==b),j=u.n.find(x=>x!==a&&x!==b);if(i===j||m.has(key(i,j)))continue;
   const ca=cross(nodes.get(i),nodes.get(j),nodes.get(a)),cb=cross(nodes.get(i),nodes.get(j),nodes.get(b));if(ca*cb>=0||Math.min(Math.abs(ca),Math.abs(cb))<=A)continue;
   let v=[i,j,a],w=[i,j,b];if(Math.min(qtri(v),qtri(w))<=Math.min(qtri(t.n),qtri(u.n))+1e-9)continue;
   live.delete(t);live.delete(u);live.add({g:t.g,tag:t.tag,n:ccw(v)});live.add({g:u.g,tag:u.tag,n:ccw(w)});count++;
  }
  ext=[...live];flips+=count;if(!count)break;
 }
 const final=[...ext,...pt.map(t=>({g:t.g,tag:tagsByGroup.get(t.g),n:ccw(t.n.map(i=>map.get(i)))}))], ids=[...new Set(final.flatMap(t=>t.n))].sort((a,b)=>a-b), edges=emap(final), bad=[...edges.values()].filter(e=>e.ts.length>2);if(bad.length)throw Error("Nonmanifold edge");
 const interfaceCounts={};for(let e of pb){let k=key(map.get(e.a),map.get(e.b)),old=cb.filter(o=>on([(p.nodes.get(e.a)[0]+p.nodes.get(e.b)[0])/2,(p.nodes.get(e.a)[1]+p.nodes.get(e.b)[1])/2],c.nodes.get(o.a),c.nodes.get(o.b)));if(old.length!==1)throw Error("Original material ambiguity");let expected=old[0].ts.find(t=>!shared(t))?.g||"external",got=edges.get(k)?.ts.find(t=>!shared(t))?.g||"external";if(got!==expected||edges.get(k)?.ts.length!==(expected==="external"?1:2))throw Error("Interface mismatch "+k+" expected "+expected+" got "+got);interfaceCounts[got]=(interfaceCounts[got]||0)+1}
 // Every edge lies on at most two triangles and has no interior vertex.
 let hanging=0;for(let e of edges.values()){let a=nodes.get(e.a),b=nodes.get(e.b);for(let j of ids){if(j===e.a||j===e.b)continue;let q=nodes.get(j);if(q[0]<Math.min(a[0],b[0])-EPS||q[0]>Math.max(a[0],b[0])+EPS||q[1]<Math.min(a[1],b[1])-EPS||q[1]>Math.max(a[1],b[1])+EPS)continue;if(on(q,a,b)){hanging++;break}}}if(hanging)throw Error("Hanging edges "+hanging);
 let duplicates=0;for(let i=0;i<ids.length;i++)for(let j=i+1;j<ids.length;j++)if(dist(nodes.get(ids[i]),nodes.get(ids[j]))<EPS)duplicates++;if(duplicates)throw Error("Duplicate nodes "+duplicates);
 function stats(ts,nd){const m={};for(let t of ts){const [a,b,c]=t.n.map(i=>nd.get(i)),area=Math.abs(cross(a,b,c))/2;const lengths=[dist(a,b),dist(b,c),dist(c,a)];const q=4*Math.sqrt(3)*area/lengths.reduce((s,x)=>s+x*x,0);let v=m[t.g]??={triangles:0,area:0,minQuality:1};v.triangles++;v.area+=area;v.minQuality=Math.min(v.minQuality,q)}return m}
 const before=stats(orig,c.nodes),after=stats(final,nodes);for(let g of Object.keys(before))if(Math.abs(before[g].area-after[g].area)>1e-12)throw Error("Area changed "+g);const oldSet=new Set(orig.filter(t=>!shared(t)).map(t=>t.tag+":"+t.n.slice().sort((a,b)=>a-b).join(",")));const unchanged=ext.filter(t=>oldSet.has(t.tag+":"+t.n.slice().sort((a,b)=>a-b).join(","))).length;

 const pn=p.sec("PhysicalNames").slice(1), cn=c.sec("PhysicalNames").slice(1);
 const names=[...pn,...cn.filter(l=>!common.has(l.match(/"([^"]+)"/)[1]))];
 const blockId=new Map(names.filter(l=>l.startsWith("2 ")).map(l=>[l.match(/"([^"]+)"/)[1],+l.split(" ")[1]]));
 const parentLines=p.sec("Elements").slice(1).map(l=>l.trim().split(/\s+/).map(Number)).filter(v=>v[1]===1);
 const pe=emap(pt);
 const orphanLines=parentLines.filter(v=>!pe.has(key(...v.slice(3+v[2]))));
 if(orphanLines.some(v=>v[3]!==1))throw Error("Non-axis orphan sideset");
 const orphanSegments=orphanLines.map(v=>v.slice(3+v[2]).map(i=>p.nodes.get(i)));
 const lineElems=parentLines.filter(v=>pe.has(key(...v.slice(3+v[2])))).map(v=>({id:v[3],n:v.slice(3+v[2]).map(i=>map.get(i))}));
 // Historical axis has 19 detached segments. Recover its exact geometric
 // extent on genuine parent triangle edges instead of importing orphan nodes.
 for(let e of pe.values()){if(e.ts.length!==1)continue;let a=p.nodes.get(e.a),b=p.nodes.get(e.b);if(a[0]!==0||b[0]!==0)continue;
  const mid=a.map((v,i)=>(v+b[i])/2);
  if(orphanSegments.some(([q,r])=>on(mid,q,r))&&!lineElems.some(l=>l.id===1&&key(...l.n)===key(map.get(e.a),map.get(e.b))))lineElems.push({id:1,n:[map.get(e.a),map.get(e.b)]});
 }
 if(lineElems.some(l=>l.n.some(i=>i===undefined)||!edges.has(key(...l.n))))throw Error("Parent sideset edge lost");
 const renum=new Map(ids.map((id,i)=>[id,i+1]));
 let lines=["$MeshFormat","2.2 0 8","$EndMeshFormat","$PhysicalNames",String(names.length),...names,"$EndPhysicalNames","$Nodes",String(ids.length),...ids.map(i=>renum.get(i)+" "+nodes.get(i).join(" ")),"$EndNodes","$Elements",String(final.length+lineElems.length)];
 let el=1;for(let l of lineElems)lines.push([el++,1,2,l.id,l.id,...l.n.map(i=>renum.get(i))].join(" "));
 for(let t of final)lines.push([el++,2,2,blockId.get(t.g),blockId.get(t.g),...t.n.map(i=>renum.get(i))].join(" "));
 lines.push("$EndElements","");
 const mesh=lines.join("\n"),round=parse(mesh);
 if(round.nodes.size!==ids.length||round.tris.length!==final.length)throw Error("Serialization mismatch");
 const canon=(ts,nd)=>ts.map(t=>t.g+":"+t.n.map(i=>nd.get(i).join(",")).sort().join(";")).sort();
 if(JSON.stringify(canon(round.tris.filter(shared),round.nodes))!==JSON.stringify(canon(pt,p.nodes)))throw Error("Parent topology mismatch");
 const oldLengths={},newLengths={};
 for(let v of parentLines){let [a,b]=v.slice(3+v[2]).map(i=>p.nodes.get(i));oldLengths[v[3]]=(oldLengths[v[3]]||0)+dist(a,b)}
 for(let v of lineElems){let [a,b]=v.n.map(i=>nodes.get(i));newLengths[v.id]=(newLengths[v.id]||0)+dist(a,b)}
 for(let k in oldLengths)if(Math.abs(oldLengths[k]-newLengths[k])>1e-10)throw Error("Boundary length drift "+k+" "+oldLengths[k]+" "+newLengths[k]);

 return {mesh,report:{parentSharedNodes:pids.length,parentSharedTriangles:pt.length,oldChildNodes:c.nodes.size,newChildNodes:ids.length,oldChildTriangles:orig.length,newChildTriangles:final.length,originalExteriorTriangles:orig.length-orig.filter(t=>shared(t)).length,unchangedExteriorTriangles:unchanged,removedInterfaceVertices:removed,insertedInterfaceVertices:inserted,interfaceCounts,hanging,duplicates,nonmanifold:bad.length,exactParentCoordinateConnectivity:true,parentBoundaryEdges:lineElems.length,physicalGroups:names.length,orphanAxisSegments:orphanLines.length,oldLengths,newLengths,flips,before,after}}
}
const [p,c,o] = process.argv.slice(2); const r=conform(fs.readFileSync(p,'utf8'),fs.readFileSync(c,'utf8')); fs.writeFileSync(o,r.mesh); console.log(JSON.stringify(r.report,null,2));

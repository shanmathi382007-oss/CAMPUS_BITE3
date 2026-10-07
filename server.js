const express=require('express'),{Pool}=require('pg'),bcrypt=require('bcryptjs'),jwt=require('jsonwebtoken');
const app=express();app.use(express.json());app.use(express.static('public'));
const SECRET=process.env.JWT_SECRET||'campusbite-dev-secret';
const pool=new Pool({host:'localhost',port:5432,user:'postgres',password:process.env.PGPASSWORD,database:'campusbite'});
const q=async(s,p)=>(await pool.query(s,p)).rows;
const wrap=f=>(req,res)=>f(req,res).catch(e=>{
 const m={'23505':[409,'Email or College ID already registered'],'23503':[409,'Cannot delete: this item is used in existing orders'],'23514':[400,'Invalid value or insufficient stock']}[e.code];
 res.status(m?m[0]:400).json({error:m?m[1]:e.message})});
const auth=role=>(req,res,next)=>{try{const u=jwt.verify((req.headers.authorization||'').slice(7),SECRET);
 if(role&&u.role!==role)return res.status(403).json({error:'Access denied'});req.user=u;next()}catch{res.status(401).json({error:'Please login'})}};
const token=u=>({token:jwt.sign({id:u.user_id,role:u.role},SECRET,{expiresIn:'8h'}),user:{id:u.user_id,name:u.name,role:u.role,email:u.email,college_id:u.college_id,department:u.department,year:u.year,phone:u.phone}});
const need=(o,...k)=>k.forEach(x=>{if(o[x]===undefined||o[x]==='')throw new Error(x+' is required')});

// ---- AUTH ----
app.post('/api/register',wrap(async(req,res)=>{const b=req.body;need(b,'name','email','password','college_id','department','phone');
 if(!/^\S+@\S+\.\S+$/.test(b.email))throw new Error('Invalid email');if(b.password.length<6)throw new Error('Password min 6 chars');
 if(!/^\d{10}$/.test(b.phone))throw new Error('Phone must be 10 digits');
 const[u]=await q('INSERT INTO users(name,email,phone,password,college_id,department,year) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING *',[b.name,b.email,b.phone,await bcrypt.hash(b.password,10),b.college_id,b.department,b.year||1]);
 res.json(token(u))}));
app.post('/api/login',wrap(async(req,res)=>{const[u]=await q('SELECT * FROM users WHERE email=$1',[req.body.email]);
 if(!u||!await bcrypt.compare(req.body.password||'',u.password))return res.status(401).json({error:'Invalid credentials'});
 if(req.body.admin&&u.role!=='admin')return res.status(403).json({error:'Not an admin account'});res.json(token(u))}));
app.put('/api/profile',auth(),wrap(async(req,res)=>{const b=req.body;need(b,'name','phone','department');
 const[u]=await q('UPDATE users SET name=$1,phone=$2,department=$3,year=$4 WHERE user_id=$5 RETURNING *',[b.name,b.phone,b.department,b.year,req.user.id]);res.json(token(u))}));

// ---- FOOD ----
app.get('/api/foods',wrap(async(req,res)=>res.json(await q(`SELECT f.*,COALESCE(ROUND(AVG(r.rating),1),0)::float AS rating,
 (SELECT COALESCE(SUM(oi.quantity),0) FROM order_items oi WHERE oi.food_id=f.food_id)::int AS sold
 FROM food_items f LEFT JOIN reviews r ON r.food_id=f.food_id GROUP BY f.food_id ORDER BY f.food_id`))));
const foodBody=b=>{need(b,'food_name','category','price','available_quantity');if(b.price<0||b.available_quantity<0)throw new Error('Negative values not allowed');
 return[b.food_name,b.category,b.description||'',b.price,b.available_quantity,b.available_quantity>0&&b.availability!==false,b.image||null]};
app.post('/api/foods',auth('admin'),wrap(async(req,res)=>{await q('INSERT INTO food_items(food_name,category,description,price,available_quantity,availability,image) VALUES($1,$2,$3,$4,$5,$6,$7)',foodBody(req.body));res.json({ok:1})}));
app.put('/api/foods/:id',auth('admin'),wrap(async(req,res)=>{await q('UPDATE food_items SET food_name=$1,category=$2,description=$3,price=$4,available_quantity=$5,availability=$6,image=$7 WHERE food_id=$8',[...foodBody(req.body),req.params.id]);res.json({ok:1})}));
app.delete('/api/foods/:id',auth('admin'),wrap(async(req,res)=>{await q('DELETE FROM food_items WHERE food_id=$1',[req.params.id]);res.json({ok:1})}));

// ---- ORDERS (transaction) ----
app.post('/api/orders',auth(),wrap(async(req,res)=>{const{items,pickup_time,method}=req.body;
 if(!Array.isArray(items)||!items.length)throw new Error('Cart is empty');need(req.body,'pickup_time','method');
 if(!['UPI','Card','Cash at Canteen'].includes(method))throw new Error('Invalid payment method');
 const c=await pool.connect();try{await c.query('BEGIN');let total=0;const rows=[];
  for(const it of items){const qty=parseInt(it.quantity);if(!(qty>0))throw new Error('Invalid quantity');
   const{rows:[f]}=await c.query('SELECT * FROM food_items WHERE food_id=$1 FOR UPDATE',[it.food_id]);
   if(!f||!f.availability||f.available_quantity<qty)throw new Error((f?f.food_name:'Item')+' is not available in that quantity');
   const price=+f.price;rows.push([f.food_id,qty,price,price*qty]);total+=price*qty}
  const paid=method!=='Cash at Canteen';
  const{rows:[o]}=await c.query('INSERT INTO orders(user_id,pickup_time,total_amount,payment_status) VALUES($1,$2,$3,$4) RETURNING order_id',[req.user.id,pickup_time,total,paid?'Paid':'Pending']);
  for(const r of rows)await c.query('INSERT INTO order_items(order_id,food_id,quantity,price,subtotal) VALUES($1,$2,$3,$4,$5)',[o.order_id,...r]); // trigger reduces stock
  await c.query('INSERT INTO payments(order_id,payment_method,amount,payment_status,transaction_id) VALUES($1,$2,$3,$4,$5)',[o.order_id,method,total,paid?'Paid':'Pending','TXN'+Date.now()]);
  await c.query('COMMIT');res.json({order_id:o.order_id,total,pickup_time,payment:paid?'Paid':'Pending'})}
 catch(e){await c.query('ROLLBACK');throw e}finally{c.release()}}));
const ORDERS=`SELECT o.*,u.name AS student,u.college_id,(SELECT string_agg(f.food_name||' × '||oi.quantity,', ')
 FROM order_items oi JOIN food_items f ON f.food_id=oi.food_id WHERE oi.order_id=o.order_id) AS items FROM orders o JOIN users u ON u.user_id=o.user_id`;
app.get('/api/orders/mine',auth(),wrap(async(req,res)=>res.json(await q(ORDERS+' WHERE o.user_id=$1 ORDER BY o.order_id DESC',[req.user.id]))));
app.post('/api/reviews',auth(),wrap(async(req,res)=>{need(req.body,'food_id','rating');await q('INSERT INTO reviews(user_id,food_id,rating,comment) VALUES($1,$2,$3,$4)',[req.user.id,req.body.food_id,req.body.rating,req.body.comment||'']);res.json({ok:1})}));

// ---- ADMIN ----
app.get('/api/admin/orders',auth('admin'),wrap(async(req,res)=>res.json(await q(ORDERS+' ORDER BY o.order_id DESC'))));
app.put('/api/admin/orders/:id/status',auth('admin'),wrap(async(req,res)=>{
 if(!['Pending','Accepted','Preparing','Ready for Pickup','Completed','Cancelled'].includes(req.body.status))throw new Error('Bad status');
 await q('CALL sp_update_order_status($1::int,$2::text)',[req.params.id,req.body.status]);res.json({ok:1})}));
app.get('/api/admin/payments',auth('admin'),wrap(async(req,res)=>res.json(await q('SELECT p.*,u.name AS student FROM payments p JOIN orders o ON o.order_id=p.order_id JOIN users u ON u.user_id=o.user_id ORDER BY p.payment_id DESC'))));
app.get('/api/admin/users',auth('admin'),wrap(async(req,res)=>res.json(await q(`SELECT u.user_id,u.college_id,u.name,u.email,u.department,u.year,
 (SELECT COUNT(*) FROM orders o WHERE o.user_id=u.user_id)::int AS total_orders FROM users u WHERE role='student'`))));
app.get('/api/admin/reports',auth('admin'),wrap(async(req,res)=>{
 const[s]=await q(`SELECT (SELECT COUNT(*) FROM users WHERE role='student')::int AS students,
  (SELECT COUNT(*) FROM orders WHERE order_date::date=CURRENT_DATE)::int AS orders_today,
  (SELECT COALESCE(SUM(total_amount),0) FROM orders WHERE order_date::date=CURRENT_DATE AND order_status<>'Cancelled') AS revenue_today,
  (SELECT COUNT(*) FROM food_items WHERE availability)::int AS available_items`);
 res.json({stats:s,daily:await q('SELECT * FROM v_daily_sales ORDER BY day DESC LIMIT 7'),popular:await q('SELECT * FROM v_popular_food LIMIT 5'),
  lowStock:await q('SELECT food_name,available_quantity FROM food_items WHERE available_quantity<=5 ORDER BY available_quantity')})}));

// ---- SEED DEMO USERS (hashed) ----
(async()=>{try{for(const[n,e,r,cid,p]of[['Demo Student','student@college.com','student','CS2024001','student123'],['Canteen Admin','admin@college.com','admin',null,'admin123']])
 await q('INSERT INTO users(name,email,phone,password,role,college_id,department,year) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT (email) DO NOTHING',[n,e,'9876543210',await bcrypt.hash(p,10),r,cid,r==='admin'?'Canteen':'CSE',2]);
 console.log('Demo users ready')}catch(e){console.error('DB error:',e.message)}})();
const PORT=process.env.PORT||3000;app.listen(PORT,'0.0.0.0',()=>console.log('CampusBite running → http://localhost:'+PORT));

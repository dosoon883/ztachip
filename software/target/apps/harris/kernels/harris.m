#include "../../../base/ztam.h"
#include "harris.h"

// Perform harris-corner algorithm
// Refer to https://en.wikipedia.org/wiki/Harris_Corner_Detector

extern void mycallback(int);

typedef struct {
   uint32_t input;
   uint32_t x_gradient;
   uint32_t y_gradient;
   uint32_t score;
   uint32_t output;
   int w;
   int h;
   int src_w;
   int src_h;
   int x_off;
   int y_off;
   int dst_w;
   int dst_h;
} Request;

// Find gradient in X and Y direction

static void harris_phase_0(void *_p,int pid) {
   Request *req=(Request *)_p;
   int from,to;
   int dx,dx2,dy;
   int dxcnt,dycnt;
   int h,pad;
   int inputLen;
   uint32_t input,x_gradient,y_gradient;
   int x,y,cnt;
   int x_off,y_off;
   int ksz=3;

   x_off=req->x_off;
   y_off=req->y_off;
   pad=(ksz/2);
   dx2=NUM_PCORE*TILE_DX_DIM;
   dx=NUM_PCORE*TILE_DX_DIM-pad;
   dy=TILE_DY_DIM*VECTOR_WIDTH;
   dxcnt=(req->w+dx-1)/dx;
   dycnt=(req->h+dy-1)/dy;
   h=(req->h+TILE_DY_DIM-1)/TILE_DY_DIM;

   if(pid==0) {
      from=0;
      to=(dycnt<=1)?dycnt:dycnt/2;
   } else {
      if(dycnt <= 1)
         return;
      from=dycnt/2;
      to=dycnt;
   }

   // Load the convolution kernel...
   > EXE_LOCKSTEP(harris::init,NUM_PCORE);
   ztamTaskYield();

   inputLen=req->src_w*req->src_h;
   input=req->input;
   inputLen-=y_off*req->src_w;
   input+=y_off*req->src_w;
   input-=req->src_w*pad;
   inputLen+=req->src_w*pad;
   x_gradient=req->x_gradient;
   y_gradient=req->y_gradient;

   for(y=from;y < to;y++) {
      for(x=0;x < dxcnt;x++) {
         cnt=NUM_PCORE;

         // Copy the left-pad from left most tiles edges from memory.
         if(x>0) {
            >(ushort)PCORE(NUM_PCORE)[0].harris::inbuf(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][0:pad-1][:] <= 
            >(ushort)PCORE(NUM_PCORE)[cnt-1].harris::inbuf(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][TILE_DX_DIM-pad:TILE_DX_DIM+pad-pad-1][:];
         } else {
            // There is nothing at the left. So set it to zero...
            >(ushort)PCORE(NUM_PCORE)[0].harris::inbuf(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][0:pad-1][:] <= SHORT(0);
         }

         // Copy input to PCORE array...
         >SCATTER(0) FOR(K=0:VECTOR_WIDTH-1) FOR(I=0:TILE_DY_DIM+2*pad-1) FOR(II=0:NUM_PCORE-1) FOR(J=pad:pad+TILE_DX_DIM-1) PCORE(NUM_PCORE)[II].harris::inbuf(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[I][J][K] <= 
         >(ushort)MEM(input|inputLen,h,TILE_DY_DIM+,req->src_w)[y*VECTOR_WIDTH:y*VECTOR_WIDTH+VECTOR_WIDTH-1][0:TILE_DY_DIM+2*pad-1][x*dx+x_off:x*dx+dx2+x_off-1];

         // Copy the gap from adjacent tile.

         // Copy left margin from right tiles to the immediate left tiles...
         >(ushort)PCORE(NUM_PCORE)[0:cnt-2].harris::inbuf(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][TILE_DX_DIM+pad:TILE_DX_DIM+2*pad-1][:] <=
         >(ushort)SYNC PCORE(NUM_PCORE)[1:cnt-1].harris::inbuf(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][pad:2*pad-1][:];

         // Copy right margin from left tiles to the immediate right tiles...
         >(ushort)PCORE(NUM_PCORE)[1:cnt-1].harris::inbuf(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][0:pad-1][:] <=
         >(ushort)PCORE(NUM_PCORE)[0:cnt-2].harris::inbuf(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][TILE_DX_DIM:TILE_DX_DIM+pad-1][:];

         if(y==0) {
            >PCORE(NUM_PCORE)[*].harris::inbuf(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[0:pad-1][:][0] <= SHORT(0);
         }

         > EXE_LOCKSTEP(harris::calc_gradient,NUM_PCORE);

         ztamTaskYield();

         // Copy result tiles back to memory
         >(int)MEM(x_gradient,req->dst_h,req->dst_w)[y*dy:y*dy+TILE_DY_DIM*VECTOR_WIDTH-1][x*dx:x*dx+dx2-1] <=
         >SCATTER(0) FOR(K=0:VECTOR_WIDTH-1) FOR(I=0:TILE_DY_DIM-1) FOR(II=0:NUM_PCORE-1) FOR(J=0:TILE_DX_DIM-1) (int)PCORE(NUM_PCORE)[II].harris::x_gradient(TILE_DY_DIM,TILE_DX_DIM,VECTOR_WIDTH)[I][J][K];

         >(int)MEM(y_gradient,req->dst_h,req->dst_w)[y*dy:y*dy+TILE_DY_DIM*VECTOR_WIDTH-1][x*dx:x*dx+dx2-1] <=
         >SCATTER(0) FOR(K=0:VECTOR_WIDTH-1) FOR(I=0:TILE_DY_DIM-1) FOR(II=0:NUM_PCORE-1) FOR(J=0:TILE_DX_DIM-1) (int)PCORE(NUM_PCORE)[II].harris::y_gradient(TILE_DY_DIM,TILE_DX_DIM,VECTOR_WIDTH)[I][J][K];
	  }
   }
}

// Calculate HARRIS score

static void harris_phase_1(void *_p,int pid) {
   Request *req=(Request *)_p;
   int from,to;
   int dx,dx2,dy;
   int dxcnt,dycnt;
   int h2,pad;
   int x_gradientLen;
   uint32_t x_gradient;
   int y_gradientLen;
   uint32_t y_gradient;
   int x,y,cnt;
   int w,h;
   int ksz=3;

   pad=(ksz/2);
   w=req->w;
   h=req->h;
   dx2=NUM_PCORE*TILE_DX_DIM;
   dx=NUM_PCORE*TILE_DX_DIM-pad;
   dy=TILE_DY_DIM*VECTOR_WIDTH;
   dxcnt=(w+dx-1)/dx;
   dycnt=(h+dy-1)/dy;
   h2=(h+TILE_DY_DIM-1)/TILE_DY_DIM;
   if(pid==0) {
      from=0;
      to=(dycnt<=1)?dycnt:dycnt/2;
   } else {
      if(dycnt <= 1)
         return;
      from=dycnt/2;
      to=dycnt;
   }

   // Load the convolution kernel...
   > EXE_LOCKSTEP(harris1::init,NUM_PCORE);
   ztamTaskYield();

   x_gradientLen=w*h*sizeof(int16_t);
   x_gradient=req->x_gradient;
   x_gradient-=w*pad*sizeof(int16_t);
   x_gradientLen+=w*pad*sizeof(int16_t);

   y_gradientLen=w*h*sizeof(int16_t);
   y_gradient=req->y_gradient;
   y_gradient-=w*pad*sizeof(int16_t);
   y_gradientLen+=w*pad*sizeof(int16_t);

   for(y=from;y < to;y++) {
      for(x=0;x < dxcnt;x++) {
         cnt=NUM_PCORE;

         // Copy the left-pad from left most tiles edges from memory.
         if(x>0) {
            >(int)PCORE(NUM_PCORE)[0].harris1::x_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][0:pad-1][:] <= 
            >(int)PCORE(NUM_PCORE)[cnt-1].harris1::x_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][TILE_DX_DIM-pad:TILE_DX_DIM+pad-pad-1][:];
            >(int)PCORE(NUM_PCORE)[0].harris1::y_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][0:pad-1][:] <= 
            >(int)PCORE(NUM_PCORE)[cnt-1].harris1::y_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][TILE_DX_DIM-pad:TILE_DX_DIM+pad-pad-1][:];
         } else {
            // There is nothing at the left. So set it to zero...
            >(int)PCORE(NUM_PCORE)[0].harris1::x_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][0:pad-1][:] <= INT(0);
            >(int)PCORE(NUM_PCORE)[0].harris1::y_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][0:pad-1][:] <= INT(0);
         }

         // Copy input to PCORE array...
         >SCATTER(0) FOR(K=0:VECTOR_WIDTH-1) FOR(I=0:TILE_DY_DIM+2*pad-1) FOR(II=0:NUM_PCORE-1) FOR(J=pad:pad+TILE_DX_DIM-1) (int) PCORE(NUM_PCORE)[II].harris1::x_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[I][J][K] <= 
         >(int)MEM(x_gradient|x_gradientLen,h2,TILE_DY_DIM+,w)[y*VECTOR_WIDTH:y*VECTOR_WIDTH+VECTOR_WIDTH-1][0:TILE_DY_DIM+2*pad-1][x*dx:x*dx+dx2-1];

         >SCATTER(0) FOR(K=0:VECTOR_WIDTH-1) FOR(I=0:TILE_DY_DIM+2*pad-1) FOR(II=0:NUM_PCORE-1) FOR(J=pad:pad+TILE_DX_DIM-1) (int) PCORE(NUM_PCORE)[II].harris1::y_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[I][J][K] <= 
         >(int)MEM(y_gradient|y_gradientLen,h2,TILE_DY_DIM+,w)[y*VECTOR_WIDTH:y*VECTOR_WIDTH+VECTOR_WIDTH-1][0:TILE_DY_DIM+2*pad-1][x*dx:x*dx+dx2-1];

         // Copy the gap from adjacent tile.

         // Copy left margin from right tiles to the immediate left tiles...
         >(int)PCORE(NUM_PCORE)[0:cnt-2].harris1::x_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][TILE_DX_DIM+pad:TILE_DX_DIM+2*pad-1][:] <=
         >(int)SYNC PCORE(NUM_PCORE)[1:cnt-1].harris1::x_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][pad:2*pad-1][:];

         // Copy right margin from left tiles to the immediate right tiles...
         >(int)PCORE(NUM_PCORE)[1:cnt-1].harris1::x_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][0:pad-1][:] <=
         >(int)PCORE(NUM_PCORE)[0:cnt-2].harris1::x_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][TILE_DX_DIM:TILE_DX_DIM+pad-1][:];

         // Copy left margin from right tiles to the immediate left tiles...
         >(int)PCORE(NUM_PCORE)[0:cnt-2].harris1::y_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][TILE_DX_DIM+pad:TILE_DX_DIM+2*pad-1][:] <=
         >(int)PCORE(NUM_PCORE)[1:cnt-1].harris1::y_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][pad:2*pad-1][:];

         // Copy right margin from left tiles to the immediate right tiles...
         >(int)PCORE(NUM_PCORE)[1:cnt-1].harris1::y_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][0:pad-1][:] <=
         >(int)PCORE(NUM_PCORE)[0:cnt-2].harris1::y_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][TILE_DX_DIM:TILE_DX_DIM+pad-1][:];

         if(y==0) {
            >(int)PCORE(NUM_PCORE)[*].harris1::x_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[0:pad-1][:][0] <= INT(0);
            >(int)PCORE(NUM_PCORE)[*].harris1::y_gradient(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[0:pad-1][:][0] <= INT(0);
         }

         > EXE_LOCKSTEP(harris1::calc,NUM_PCORE);

         ztamTaskYield();

         // Copy result tiles back to memory
         >(int)MEM(req->score,h,w)[y*dy:y*dy+TILE_DY_DIM*VECTOR_WIDTH-1][x*dx:x*dx+dx2-1] <=
         >SCATTER(0) FOR(K=0:VECTOR_WIDTH-1) FOR(I=0:TILE_DY_DIM-1) FOR(II=0:NUM_PCORE-1) FOR(J=0:TILE_DX_DIM-1) (int)PCORE(NUM_PCORE)[II].harris1::score(TILE_DY_DIM,TILE_DX_DIM,VECTOR_WIDTH)[I][J][K];
      }
   }
}

// Local non-max suppression

static void harris_phase_2(void *_p,int pid) {
   Request *req=(Request *)_p;
   int from,to;
   int dx,dx2,dy;
   int dxcnt,dycnt;
   int h2,pad;
   int scoreLen;
   uint32_t score;
   int x,y,cnt;
   int w,h;
   int ksz=3;

   pad=(ksz/2);
   w=req->w;
   h=req->h;
   dx2=NUM_PCORE*TILE_DX_DIM;
   dx=NUM_PCORE*TILE_DX_DIM-pad;
   dy=TILE_DY_DIM*VECTOR_WIDTH;
   dxcnt=(w+dx-1)/dx;
   dycnt=(h+dy-1)/dy;
   h2=(h+TILE_DY_DIM-1)/TILE_DY_DIM;
   if(pid==0) {
      from=0;
      to=(dycnt<=1)?dycnt:dycnt/2;
   } else {
      if(dycnt <= 1)
         return;
      from=dycnt/2;
      to=dycnt;
   }

   // Load the convolution kernel...
   > EXE_LOCKSTEP(harris2::init,NUM_PCORE);
   ztamTaskYield();

   scoreLen=w*h*sizeof(int16_t);
   score=req->score;
   score-=w*pad*sizeof(int16_t);
   scoreLen+=w*pad*sizeof(int16_t);

   for(y=from;y < to;y++) {
      for(x=0;x < dxcnt;x++) {
         cnt=NUM_PCORE;

         // Copy the left-pad from left most tiles edges from memory.
         if(x>0) {
            >(int)PCORE(NUM_PCORE)[0].harris2::score(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][0:pad-1][:] <= 
            >(int)PCORE(NUM_PCORE)[cnt-1].harris2::score(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][TILE_DX_DIM-pad:TILE_DX_DIM+pad-pad-1][:];
         } else {
            // There is nothing at the left. So set it to zero...
            >(int)PCORE(NUM_PCORE)[0].harris2::score(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][0:pad-1][:] <= INT(0);
         }

         // Copy input to PCORE array...
         >SCATTER(0) FOR(K=0:VECTOR_WIDTH-1) FOR(I=0:TILE_DY_DIM+2*pad-1) FOR(II=0:NUM_PCORE-1) FOR(J=pad:pad+TILE_DX_DIM-1) (int) PCORE(NUM_PCORE)[II].harris2::score(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[I][J][K] <= 
         >(int)MEM(score|scoreLen,h2,TILE_DY_DIM+,w)[y*VECTOR_WIDTH:y*VECTOR_WIDTH+VECTOR_WIDTH-1][0:TILE_DY_DIM+2*pad-1][x*dx:x*dx+dx2-1];

         // Copy the gap from adjacent tile.

         // Copy left margin from right tiles to the immediate left tiles...
         >(int)PCORE(NUM_PCORE)[0:cnt-2].harris2::score(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][TILE_DX_DIM+pad:TILE_DX_DIM+2*pad-1][:] <=
         >(int)SYNC PCORE(NUM_PCORE)[1:cnt-1].harris2::score(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][pad:2*pad-1][:];

         // Copy right margin from left tiles to the immediate right tiles...
         >(int)PCORE(NUM_PCORE)[1:cnt-1].harris2::score(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][0:pad-1][:] <=
         >(int)PCORE(NUM_PCORE)[0:cnt-2].harris2::score(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[:][TILE_DX_DIM:TILE_DX_DIM+pad-1][:];

         if(y==0) {
            >(int)PCORE(NUM_PCORE)[*].harris2::score(TILE_DY_DIM+2*pad,TILE_DX_DIM+2*pad,VECTOR_WIDTH)[0:pad-1][:][0] <= INT(0);
         }

         > EXE_LOCKSTEP(harris2::calc,NUM_PCORE);

         ztamTaskYield();

         // Copy result tiles back to memory
         >(int)MEM(req->output,h,w)[y*dy:y*dy+TILE_DY_DIM*VECTOR_WIDTH-1][x*dx:x*dx+dx2-1] <=
         >SCATTER(0) FOR(K=0:VECTOR_WIDTH-1) FOR(I=0:TILE_DY_DIM-1) FOR(II=0:NUM_PCORE-1) FOR(J=0:TILE_DX_DIM-1) (int)PCORE(NUM_PCORE)[II].harris2::output(TILE_DY_DIM,TILE_DX_DIM,VECTOR_WIDTH)[I][J][K];
      }
   }
}

// Process request from host to do harris-corner feature extraction

void do_harris(int queue)
{
   Request req;
   int resp;

   req.input=ztamMsgqReadPointer(queue);
   req.x_gradient=ztamMsgqReadPointer(queue);
   req.y_gradient=ztamMsgqReadPointer(queue);
   req.score=ztamMsgqReadPointer(queue);
   req.output=ztamMsgqReadPointer(queue);
   req.w=ztamMsgqReadInt(queue);
   req.h=ztamMsgqReadInt(queue);
   req.src_w=ztamMsgqReadInt(queue);
   req.src_h=ztamMsgqReadInt(queue);
   req.x_off=ztamMsgqReadInt(queue);
   req.y_off=ztamMsgqReadInt(queue);
   req.dst_w=ztamMsgqReadInt(queue);
   req.dst_h=ztamMsgqReadInt(queue);
   resp=ztamMsgqReadInt(queue);
   ztamTaskSpawn(harris_phase_0,&req,1);
   harris_phase_0(&req,0);
   while(ztamTaskStatus(1))
      ztamTaskYield();
   ztamTaskSpawn(harris_phase_1,&req,1);
   harris_phase_1(&req,0);
   while(ztamTaskStatus(1))
      ztamTaskYield();
   ztamTaskSpawn(harris_phase_2,&req,1);
   harris_phase_2(&req,0);
   while(ztamTaskStatus(1))
      ztamTaskYield();
   if(resp >= 0)
      >CALLBACK(mycallback,resp);
}

> EXPORT(do_harris);

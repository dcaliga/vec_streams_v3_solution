/*
 * Copyright 2005 SRC Computers, Inc.  All Rights Reserved.
 *
 *	Manufactured in the United States of America.
 *
 * SRC Computers, Inc.
 * 4240 N Nevada Avenue
 * Colorado Springs, CO 80907
 * (v) (719) 262-0213
 * (f) (719) 262-0223
 *
 * No permission has been granted to distribute this software
 * without the express permission of SRC Computers, Inc.
 *
 * This program is distributed WITHOUT ANY WARRANTY OF ANY KIND.
 */

#include <libmap.h>

#define DO_LE

void subr (int64_t A[], int64_t B[], int64_t Out[], int32_t Counts[], int nvec, int nspin, 
           int *nout, int64_t *time, int mapnum) {

    OBM_BANK_A (AL,      int64_t, MAX_OBM_SIZE)
    OBM_BANK_B (BL,      int64_t, MAX_OBM_SIZE)
    OBM_BANK_C (CountsL, int64_t, MAX_OBM_SIZE)

    int64_t t0, t1, t2;
    int i,n,total_nsamp,istart,cnt;
    int total_nsampA;
    int total_nsampB;
    int nputa,nputb;
    
    Stream_64 SB,SA,SC,SOut;
    Stream_32 SAC,SBC;
    Vec_Stream_64 VSA,VSB,VSM64;
    Vec_Stream_256 VSA_op,VSB_op,VSM;

    read_timer (&t0);

    nputa = 0;
    nputb = 0;

#pragma src parallel sections
{
#pragma src section
{
    streamed_dma_cpu_64 (&SC, PORT_TO_STREAM, Counts, nvec*sizeof(int64_t));
}
#pragma src section
{
    int i,cnta,cntb,na,nb;
    int64_t i64;

    for (i=0;i<nvec;i++)  {
       get_stream_64 (&SC, &i64);
       CountsL[i] = i64;
       split_64to32 (i64, &cntb, &cnta);
       cg_accum_add_32 (cnta, 1, 0, i==0, &total_nsampA);
       cg_accum_add_32 (cntb, 1, 0, i==0, &total_nsampB);

       na = (cnta+3)/4; nb = (cntb+3)/4;
       cg_accum_add_32 (na, 1, 0, i==0, &nputa);
       cg_accum_add_32 (nb, 1, 0, i==0, &nputb);
    }
 
 printf ("nsampA %i\n",total_nsampA);
 printf ("nsampB %i\n",total_nsampB);
 total_nsamp = total_nsampA + total_nsampB;
}
}

#pragma src parallel sections
{
#pragma src section
{
    streamed_dma_cpu_64 (&SA, PORT_TO_STREAM, A, total_nsampA*sizeof(int64_t));
}
#pragma src section
{
    int i;
    int64_t i64;

    for (i=0;i<total_nsampA;i++)  {
       get_stream_64 (&SA, &i64);
       AL[i] = i64;
    }
}
}

#pragma src parallel sections
{
#pragma src section
{
    streamed_dma_cpu_64 (&SB, PORT_TO_STREAM, B, total_nsampB*sizeof(int64_t));
}
#pragma src section
{
    int i;
    int64_t i64;

    for (i=0;i<total_nsampB;i++)  {
       get_stream_64 (&SB, &i64);
       BL[i] = i64;
    }
}
}

#pragma src parallel sections
{
#pragma src section
{
    int n,i,cnta,cntb;
    int64_t i64;

    for (n=0;n<nvec;n++)  {
      i64 = CountsL[n];
      split_64to32 (i64, &cntb, &cnta);

      put_stream_32 (&SAC, cnta, 1);
      put_stream_32 (&SBC, cntb, 1);
   }
}
    
#pragma src section
{
    int n,nn,i,cnt,istart;
    int64_t i64;

    istart = 0;
    for (n=0;n<nvec;n++)  {
      get_stream_32 (&SAC, &cnt);

   if (n==0) spin_wait(nspin);

      nn = n+1;
      comb_32to64 (nn, cnt, &i64);
      put_vec_stream_64_header (&VSA, i64);

      for (i=0; i<cnt; i++) {
        put_vec_stream_64 (&VSA, AL[i+istart], 1);
      }
      istart = istart + cnt;

      put_vec_stream_64_tail   (&VSA, 1234);
    }
    vec_stream_64_term (&VSA);
}
#pragma src section
{
    int n,nn,i,cnt,istart;
    int64_t i64;

    istart = 0;
    for (n=0;n<nvec;n++)  {
      get_stream_32 (&SBC, &cnt);

   if (n==0) spin_wait(1);

      nn = n+1;
      comb_32to64 (nn, cnt, &i64);
      put_vec_stream_64_header (&VSB, i64);

      for (i=0; i<cnt; i++) {
        put_vec_stream_64 (&VSB, BL[i+istart], 1);
      }
      istart = istart + cnt;

      put_vec_stream_64_tail   (&VSB, 1234);
    }
    vec_stream_64_term (&VSB);
}

// *****************************
// perform operation unique to A stream
// add line number * 10000 
// *****************************
#pragma src section
{
    int i,n,cnt,iput;
    int64_t v0,v1,i64;
    int64_t t0,t1,t2,t3;
    int64_t s0,s1,s2,s3;

    while (is_vec_stream_64_active(&VSA)) {
      get_vec_stream_64_header (&VSA, &i64);
      split_64to32 (i64, &n, &cnt);

 printf ("VSA cnt %i\n",cnt);

#ifdef DO_LE
      put_vec_stream_256_header (&VSA_op, i64,0,0,0);
#else
      put_vec_stream_256_header (&VSA_op, 0,0,0,i64);
#endif

      for (i=0;i<cnt;i++)  {
        get_vec_stream_64 (&VSA, &v0);

        v1 = v0 + n*10000;
      //  v1 = v0 + n*65536;
        s0 = s1;
        s1 = s2;
        s2 = s3;
        s3 = v1;

    printf ("VSA v1 %lld\n",v1);

        iput = ((i+1)%4 == 0) ? 1 : 0;
        if (i==cnt-1) iput = 1;

        if      (iput & (i%4)==0) {t0 = s3; t1 = 0;  t2 = 0;  t3 = 0; }
        else if (iput & (i%4)==1) {t0 = s2; t1 = s3; t2 = 0;  t3 = 0; }
        else if (iput & (i%4)==2) {t0 = s1; t1 = s2; t2 = s3; t3 = 0; }
        else if (iput & (i%4)==3) {t0 = s0; t1 = s1; t2 = s2; t3 = s3; }

 if (iput) {
 printf ("VSA s0-3 %lld %lld %lld %lld\n",s0,s1,s2,s3);
 printf ("VSA t0-3 %lld %lld %lld %lld\n",t0,t1,t2,t3);
  }

#ifdef DO_LE
      put_vec_stream_256 (&VSA_op, t3,t2,t1,t0, iput);
#else
      put_vec_stream_256 (&VSA_op, t0,t1,t2,t3, iput);
#endif

      }

      get_vec_stream_64_tail   (&VSA, &i64);
      put_vec_stream_256_tail  (&VSA_op, 0,0,0,0);
    }
    vec_stream_256_term (&VSA_op);
}

// *****************************
// perform operation unique to B stream
// add line number * 1000000 
// *****************************
#pragma src section
{
    int i,n,cnt,iput;
    int64_t v0,v1,i64;
    int64_t t0,t1,t2,t3;
    int64_t s0,s1,s2,s3;

    while (is_vec_stream_64_active(&VSB)) {
      get_vec_stream_64_header (&VSB, &i64);
      split_64to32 (i64, &n, &cnt);

// bumped n to see after merge
      n = n+1000;
      comb_32to64 (n, cnt,&i64);

 printf ("VSB cnt %i\n",cnt);

#ifdef DO_LE
      put_vec_stream_256_header (&VSB_op, i64,0,0,0);
#else
      put_vec_stream_256_header (&VSB_op, 0,0,0,i64);
#endif

      for (i=0;i<cnt;i++)  {
        get_vec_stream_64 (&VSB, &v0);

        v1 = v0 + n*1000000;
   //     v1 = v0 + n*1048576;
        s0 = s1;
        s1 = s2;
        s2 = s3;
        s3 = v1;

  
        iput = ((i+1)%4 == 0) ? 1 : 0;
        if (i==cnt-1) iput = 1;

        if      (iput & (i%4)==0) {t0 = s3; t1 = 0;  t2 = 0;  t3 = 0; }
        else if (iput & (i%4)==1) {t0 = s2; t1 = s3; t2 = 0;  t3 = 0; }
        else if (iput & (i%4)==2) {t0 = s1; t1 = s2; t2 = s3; t3 = 0; }
        else if (iput & (i%4)==3) {t0 = s0; t1 = s1; t2 = s2; t3 = s3; }


#ifdef DO_LE
        put_vec_stream_256 (&VSB_op, t3,t2,t1,t0, iput);
#else
        put_vec_stream_256 (&VSB_op, t0,t1,t2,t3, iput);
#endif
      }

      get_vec_stream_64_tail   (&VSB, &i64);
      put_vec_stream_256_tail   (&VSB_op, 0,0,0,0);
    }
    vec_stream_256_term (&VSB_op);
}

// *****************************
// merge A and B streams
// *****************************
#pragma src section
{
    //vec_stream_merge_nd_2_256_term (&VSA_op, &VSB_op, &VSM);
    vec_stream_merge_2_256_term (&VSA_op, &VSB_op, &VSM);
}

#pragma src section
{
#ifdef DO_LE
    vec_stream_width_256to64_le_term (&VSM, &VSM64);
#else
    vec_stream_width_256to64_term (&VSM, &VSM64);
#endif
}

#pragma src section
{
    int i,n,cnt,cnt4,iput;
    int64_t h0,h1,h2,h3;
    int64_t v0,v1,v2,v3;

    istart = 0;
    while (is_vec_stream_64_active(&VSM64)) {
      get_vec_stream_64_header (&VSM64, &h0);
      split_64to32 (h0, &n, &cnt);


//*****************************
// Note we could use a for loop
// or use the while all_vec_streams_active
//*****************************
//    cnt4 = ((cnt+3)/4)*4;
//    for (i=0;i<cnt4;i++)  {

      i = 0;
      while (all_vec_streams_active())  {
        get_vec_stream_64 (&VSM64, &v0);

        put_stream_64 (&SOut, v0, i<cnt);

      if (i<cnt) printf ("VSM body v0 %lld\n",v0);
      i++;
      }

      get_vec_stream_64_tail   (&VSM64, &h0);
    }
}
#pragma src section
{
    *nout = total_nsamp;
    streamed_dma_cpu_64 (&SOut, STREAM_TO_PORT, Out, (total_nsamp)*sizeof(int64_t));

}
}
    read_timer (&t1);
    *time = t1 - t0;
    }

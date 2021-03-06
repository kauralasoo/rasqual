Quantile <-
function(x,k=20){x=rank(x,ties="random"); z=rep(0,length(x));for(i in 1:k){z=z+as.numeric(x<=quantile(x,i/k,na.rm=T))};k-z}
gcCor <-
function(Y,gcvec,PLOT=F){
	bin=Quantile(gcvec,200);
	x=sort(unlist(lapply(split(gcvec,bin),mean)))
	S=apply(Y,2,function(y){unlist(lapply(split(y,bin),sum))[as.character(0:199)]});
	Fs=log(t(t(S)/apply(S,2,sum))/apply(S,1,sum)*sum(S));
	Gs=apply(Fs,2,function(y){smooth.spline(x,y,spar=1)$y}); 
	if(PLOT){
		par(mfcol=c(5,5),mar=c(2,2,2,2)); 
		for(i in 1:ncol(Y)){
			plot(Fs[,i])
			lines(Gs[,i],col=2)
		}
		matplot(x,Gs,type="l",col=2,lty=1)
	}
	exp(Gs[bin+1,])
}

function [AL,AR,AC,C] = fVUMPS_MPO_multi(W,N,params)
%UNTITLED2 Summary of this function goes here
%   Detailed explanation goes here

d = W.d;
dw = W.dw;
% PBC index function (wraps around, s.t. FP(N+1) = 1 and FP(0) = N)
PBC = @(n)(mod(n+N-1,N)+1);

% tol0 = 1e-15;
tolmax = 1e-6;

% mmax = params.mmax;
mv = params.mv;
Nm = zeros(1,N);
if ~iscell(mv),
    Nm = length(mv)*ones(N,1);
    mv = repmat({mv},N,1);
else
    assert(length(mv)==N,'mv needs to be of length N');
    for nn=1:N
        Nm(nn) = length(mv{nn});
        reshape(mv{nn},[1,Nm(nn)]);
    end
end

% if length(mmax)==1,mmax=mmax*ones(N,1);end
% assert(length(mmax)==N,'mmax needs to be of length N');

if isfield(params,'thresh'),thresh=params.thresh;
else thresh = 1e-12;
end

if isfield(params,'expthresh'),expthresh=params.expthresh;
else expthresh = 1e-5;
end

if isfield(params,'SVDthresh'),SVDthresh=params.SVDthresh;
else SVDthresh = 1e-6;
end

if isfield(params,'InvEthresh'),InvEthresh=params.InvEthresh;
else InvEthresh = 1e-14;
end

if isfield(params,'Eigsthresh'),tolmin=params.Eigsthresh;
else tolmin = 2*eps;
end

frmt = sprintf('%%2.%ue',ceil(-log10(thresh)));

if isfield(params,'lamthresh'),lamthresh=params.lamthresh;
else lamthresh = 1e-8;
end

if isfield(params,'dm'),dmmax=params.dm;
else dmmax = 10;
end

if isfield(params,'plotlam'),plotlam=params.plotlam;
else plotlam=false;
end

if isfield(params,'plotnorm'),plotnorm=params.plotnorm;
else plotnorm = false;
end

if isfield(params,'plotvst'),plotvst=params.plotvst;
else plotvst = false;
end

if isfield(params,'verbose'),verbose=params.verbose;
else verbose=true;
end

if isfield(params,'checkpoint')
    chkp=params.checkpoint;
    if ~islogical(chkp)
        warning('checkpoint is not a logical variable, setting true');
        chkp = true;
    end
else chkp=false;
end

if isfield(params,'resume')
    resumefile=params.resume;
    if exist(resumefile,'file') ~= 2
        warning([resumefile,' does not exist, starting from scratch']);
        resumefile=[];
    end
else resumefile=[];
end

if isfield(params,'obs'),obsop=params.obs;
else obsop=[];
end

if chkp
    dchkp = 5;
    chkpname = ['chkp_',datestr(now,'yymmdd_HHMMSS.FFF'),'.mat'];
    %     c=1;
    %     while exist(['chkp',num2str(c,'%03u'),'.mat'],'file') == 2,c = c+1;end
    %     chkpname = ['chkp',num2str(c,'%03u'),'.mat'];
end


if isempty(resumefile)
    if isfield(params,'A0')
        AL0 = params.A0.AL;
        AR0 = params.A0.AR;
        C0 = params.A0.C;
        N = length(AL0);
        assert(iscell(AL0{1}),'AL0 needs to be a cell of cells');
        assert(iscell(AR0{1}),'AR0 needs to be a cell of cells');
        assert(length(AR0)==N,'AR0 has wrong unit cell size');
        assert(length(C0)==N,'C0 has wrong unit cell size');
        
        assert(length(AL0{1})==d,'AL0 has wrong physical dimension');
        assert(length(AR0{1})==d,'AR0 has wrong physical dimension');
        
        m0 = zeros(1,N);
        lam0 = cell(1,N);
        for nn=1:N
            lam0{nn} = svd(C0{nn});
            m0(nn) = size(AL0{nn}{1},1);
            
            if mv{nn}(1) ~= m0(nn)
                mv{nn} = [m0,mv{nn}(mv{nn}>m0(nn))];
            end
            assert(size(AL0{PBC(nn-1)}{1},2)==m0(nn),['AL0{',int2str(PBC(nn-1)),'} and AL0{',int2str(nn),'} must have matching bond dimensions']);
            assert(size(AR0{PBC(nn-1)}{1},2)==m0(nn),['AR0{',int2str(PBC(nn-1)),'} and AR0{',int2str(nn),'} must have matching bond dimensions']);
        end
        
        CheckOrthoLRSqrt(AL0,AR0,C0,1);
        cmplx = ~all(cellfun(@isreal,C0));
        
        
    else
        m0 = cellfun(@(x)(x(1)),mv);
        
        if isfield(params,'cmplx'),cmplx=params.cmplx;
        else cmplx = false;
        end
        
        [AL0,AR0,C0] = randMPS_LR(d,m0,N,cmplx);
        lam0 = cellfun(@(x)(svd(x)),C0,'uniformoutput',false);
    end
    
    AL = AL0;
    AR = AR0;
    C = C0;
    lam = lam0;
    
else
    F=load(resumefile);
    AL=F.AL;
    AR=F.AR;
    C=F.C;
    assert(length(AL)==N,'AL has wrong physical dimensions');
    assert(length(AL{1})==d,'AL has wrong physical dimensions');
    lam = cellfun(@svd,C,'uniformoutput',false);
    m0 = zeros(1,N);
    for nn=1:N
        m0(nn) = length(lam{nn});
        if mv{nn}(1) ~= m0(nn)
            mv{nn} = [m0,mv{nn}(mv{nn}>m0(nn))];
        end
    end
    disp([resumefile,' loaded']);
end

AC=cell(1,N);
for nn=1:N
    AC{nn} = cellfun(@(x)(x*C{nn}),AL{nn},'uniformoutput',false);
end

% inital relative shift
AR = [AR(2:end),AR(1)];

% C = lam0;
% Sold = cellfun(@(x)(-dot(diag(x),log2(diag(x)))),lam0,'uniformoutput',true);
% disp(Sold);
% dS = 1;
dosvd = true;
% prec = 1e-2;

%%

WN = W;
for nn=2:N
    WN = concatMPO(WN,W);
end


R = C{end}*C{end}';
XLtmp = fMPO_TMeig(AL,WN,[],R,'l');
XL = XLtmp;

L = C{1}'*C{1};
XR = fMPO_TMeig(AR,WN,L,[],'r');

XL1 = ApplyMPOTM(AL{1},AL{1},W,XL,'l');
XR1 = ApplyMPOTM(AR{end},AR{end},W,XR,'r');

tmpr = ApplyMPOTM(AR,AR,WN,XR,'r');
Eold = trace(L*tmpr{end})/N;
% tmpl = ApplyMPOTM(AL,AL,WN,XL,'l');
% Eold = trace(tmpl{1}*R)/N;

if plotlam
    fhlam = figure;
    ahlam = axes('yscale','log');
    lhlam1 = line(1,1,'linestyle','none','marker','.','color','g','parent',ahlam);
    lhlam2 = line(1,1,'linestyle','none','marker','o','color','b','parent',ahlam);
    xlabel('# of Schmidt Value \lambda');
    ylabel('log(\lambda)');
end

if plotnorm
    Fv = [];
    if isfield(params,'ahnrm')
        ahnrm = params.ahnrm;
    else
        fhnrm = figure;
        ahnrm = axes('yscale','log');
        if plotvst,xlabel('t [s]');
        else xlabel('k');
        end
        ylabel('|F|','rotation',0);
    end
    lhnrm = line(1,1,'marker','.','color','k','parent',ahnrm);
    drawnow;
end

plotex = false;
if isfield(params,'Eex')
    Eex = params.Eex;
    dev = Eold-Eex;
    plotex = true;
    if isfield(params,'ahex'),ahex = params.ahex;
    else
        figure;
        ahex = axes('yscale','log');
        if plotvst,xlabel('t [s]');
        else xlabel('k');
        end
        ylabel('\Deltae','rotation',0);
    end
    lhex = line(1,1,'marker','.','color','b','parent',ahex);
end

%% actual VUMPS iteration
errs = ones(N,3);
prec = ones(1,N);
F = ones(1,N);

tv = 0;
ttot = 0;
ct=0;
mct = ones(1,N);
dexct = 5;
exct = zeros(1,N);

opts.isreal = ~cmplx;
opts.issym = true;
if cmplx,mode = 'SR';
else mode = 'SA';
end

XL0 = cell(1,N);
XR0 = cell(1,N);

run_vumps = true;
while run_vumps
    
    ct = ct + 1;
    for nn=1:N
        tstep = 0;
        F(nn) = fGradNorm(AL{1},C{1}, @(X)(fApplyHAMPO(X,XLtmp,XR,W)));
%         tol = min(max(F(nn)/100,tolmin),tolmax);
        tol = min(max(prec(nn)/100,tolmin),tolmax);
%         pause;
        
        XL0{PBC(nn)} = XL;
        XR0{PBC(nn)} = XR;
        
        ml = size(XL{1},2);
        mr = size(XR{end},1);
        HAfun = @(x)(reshape(cell2mat(fApplyHAMPO(mat2cell(reshape(x,d*ml,mr),ml*ones(d,1),mr),XL,XR,W)),d*ml*mr,1));
        HCLfun = @(x)(reshape(fApplyHCMPO(reshape(x,ml,ml),XL,XR1),ml*ml,1));
        HCRfun = @(x)(reshape(fApplyHCMPO(reshape(x,mr,mr),XL1,XR),mr*mr,1));
        
        opts.tol = tol;
    
        if ~isequal(size(AC{1}),[ml,mr])
            for kk=1:d,AC{1}{kk} = C{end}*AR{end}{kk};end
        end
        
        tic;
        opts.v0 = reshape(cell2mat(AC{1}),d*ml*mr,1);% here AC0 helps!
        [ACv,~] = eigs(HAfun,d*ml*mr,1,mode,opts);
        AC{1} = mat2cell(reshape(ACv,d*ml,mr),ml*ones(d,1),mr);
        
        opts.v0 = reshape(C{end},ml*ml,1); % here CL0 helps!
        [CLv,~] = eigs(HCLfun,ml*ml,1,mode,opts);
        CL = reshape(CLv,ml,ml);
        
        opts.v0 = reshape(C{1},mr*mr,1); % here CR0 helps!
        [CRv,~] = eigs(HCRfun,mr*mr,1,mode,opts);
        CR = reshape(CRv,mr,mr);
        tstep = tstep + toc;
        
        [UCL,lamL,VCL] = svd(CL);
        [UCR,lamR,VCR] = svd(CR);
        lamL = diag(lamL);
        lamR = diag(lamR);
        
%         if dosvd && min([lamL(end),lamR(end),F(nn)])<SVDTol, dosvd=false;disp('switching');end
        if dosvd && F(nn)<SVDthresh
            dosvd=false;
%             disp('switching');
%             pause;
        end
        
        tic;
        if dosvd
            [UL,~,VL] = svd(cell2mat(AC{1})*CR','econ');
            AL{1} = mat2cell(UL*VL',ml*ones(d,1),mr);
            
            [UR,~,VR] = svd(CL'*cell2mat(AC{1}.'),'econ'); %% AC.' just reshapes the [2,1] cell into a [1,2] one
            AR{end} = mat2cell(UR*VR',ml,mr*ones(1,d));
        else
            % Matt's new scheme (polar decompositions)
            
            [UAL,~,VAL] = svd(cell2mat(AC{1}),'econ');
            [UAR,~,VAR] = svd(cell2mat(AC{1}.'),'econ');
            
            AL{1} = mat2cell(UAL*VAL'*VCR*UCR',ml*ones(d,1),mr);
            AR{end} = mat2cell(VCL*UCL'*UAR*VAR',ml,mr*ones(1,d));
            
%             % old QR scheme
%             [QAL,~] = qrpos(cell2mat(AC{1}));
%             [QCL,~] = qrpos(CR);
%             AL{1} = mat2cell(QAL*QCL',ml*ones(d,1),mr);
%             
%             [QAR,~] = qrpos(cell2mat(AC{1}.')');
%             [QCR,~] = qrpos(CL');
%             AR{end} = mat2cell(QCR*QAR',ml,mr*ones(1,d));
        end
        tstep = tstep + toc;
        
        C{1} = CR;
        C{end} = CL;
        lam{1} = lamR;
        lam{end} = lamL;
        
        errs(nn,1) = max(max(abs(cell2mat(AC{1}) - cell2mat(AL{1})*C{1})));
        errs(nn,2) = max(max(abs(cell2mat(AC{1}.') - C{end}*cell2mat(AR{end}))));
        tmp = cell(d,1);
        for kk=1:d,tmp{kk} = AL{1}{kk}*C{1} - C{end}*AR{end}{kk};end
        errs(nn,3) = max(max(abs(cell2mat(tmp))));
        prec(nn) = max(errs(nn,:));
        
        
        if plotlam
            set(lhlam1,'xdata',1:length(lamL),'ydata',lamL);
            set(lhlam2,'xdata',1:length(lamR),'ydata',lamR);
            title(ahlam,['step ',int2str(ct),', site ',int2str(nn)]);
            legend(ahlam,{['\lambda_',int2str(PBC(nn-1))],['\lambda_',int2str(nn)]},'location','best');
            drawnow;
        end
        
        
        tic;
%         XL = fMPO_TMeig(AL,WN,[],C{end}*C{end}','l',InvEthresh,max(InvEthresh,max(prec)/10),XL0{nn}); % here XL0 helps
        XL = fMPO_TMeig(AL,WN,[],C{end}*C{end}','l',InvEthresh,max(InvEthresh,tol),XL0{nn}); % here XL0 helps
        tstep = tstep + toc;
        
        % move one site to the right within the unit cell %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        AL=[AL(2:end),AL(1)];
        AR=[AR(2:end),AR(1)];
        AC=[AC(2:end),AC(1)];
        C=[C(2:end),C(1)];
        lam=[lam(2:end),lam(1)];
        
        tic;
%         XR = fMPO_TMeig(AR,WN,C{1}'*C{1},[],'r',InvEthresh,max(InvEthresh,max(prec)/10),XR0{PBC(nn+1)}); % here XR0 DOES NOT HELP!! How to fix??
        XR = fMPO_TMeig(AR,WN,C{1}'*C{1},[],'r',InvEthresh,max(InvEthresh,tol),XR0{PBC(nn+1)}); % here XR0 DOES NOT HELP!! How to fix??
        tstep = tstep + toc;
       
        % maybe subtract contribution from dominant subspace from XL{1}?
        XLtmp = ApplyMPOTM(AL{end},AL{end},W,XL,'l');
        XL1 = ApplyMPOTM(AL{1},AL{1},W,XLtmp,'l');
        
%         expandnow = [exct(nn) > dexct, F(nn)< expthresh, mr < mmax(nn), lamR(end) > lamthresh];
        expandnow = [exct(nn) > dexct, prec(PBC(nn+1))< expthresh, mct(nn) < Nm(nn), lamR(end) > lamthresh];
        
        if all(expandnow)
            exct(nn) = 0;
            mct(nn) = mct(nn) + 1;
            
            mnew = mv{nn}(mct(nn));
            [dm,ALnew,Cnew,ARnew] = fExpandMPO(W,XL,XR,AL{end},AR{end},C{end},mnew-mr);
            
            if dm ~= mnew-mr,warning(['new bond dimension is m(',int2str(nn),'=',int2str(mr+dm)]);end
            AL{end} = ALnew;
            AR{end} = ARnew;
            C{end} = Cnew;
            
            mltmp = size(AR{end-1}{1},1);
            for kk=1:d
                AR{end-1}{kk} = [AR{end-1}{kk},zeros(mltmp,dm)];
            end
            XL = ApplyMPOTM(ALnew,ALnew,W,XL,'l');
            XR1 = ApplyMPOTM(ARnew,ARnew,W,XR,'r');
        else
            exct(nn) = exct(nn) + 1;
            XL = XLtmp;
            XR1 = ApplyMPOTM(AR{end},AR{end},W,XR,'r');
        end
    end
    
    ttot = ttot + tstep;
    if verbose
        % in order to get truly variational energies, calculate exact left dominant TM eigenvector
        L = fMPSTMeig(AR,'l',0,C{1}'*C{1});
        E = EdensMPO(AR,WN,XR,L,'r')/N; % this is a translation over an entire unit cell and measures the energy of one unit cell
        dE = E - Eold;
        Eold = E;
        tmpfrmt = get(0,'format');
        format long e;
        disp('=================================================================================================================');
        disp([int2str(ct),': E = ',num2str(E,frmt),', dE = ',num2str(dE)]);

        
        if ~isempty(obsop)
            nops = length(obsop);
            obs = zeros(N,nops);
            for nn=1:N
                for kk=1:nops
                    assert(obsop(kk).sites == 1,'only single site implemented');
                    obs(nn,kk) = trace(ApplySingleOp(AC{nn},AC{nn},[],obsop(kk).op,'l'));
                end
            end
            disp({obsop.name});
            format long e;
            disp(obs);
            disp('means:');
            disp(mean(obs));
            format short;
        end
        disp('errors');
        disp(errs);
        disp(['errmax: ',num2str(max(errs)),', total: ',num2str(max(errs(:)))]);
        disp('gradient norms');
        disp(F);
        disp(['FMax: ',num2str(max(F))]);
%         CheckOrthoLRSqrt(AL,[AR(end),AR(1:end-1)],C,1);
        format(tmpfrmt);
    end
    
    mtoosmall = false(1,N);
    lamtoobig = false(1,N);
    for nn=1:N
        mtoosmall(nn) = mct(nn)<Nm(nn);
        lamtoobig(nn) = lam{nn}(end)>lamthresh;
    end
    
    % plot evolution of gradient norm
    if plotnorm
        Fv = [Fv;max(F)];
        if plotvst
            tv = [tv;ttot];
            xdat = tv(2:end);
        else
            xdat = (1:length(Fv))+1;
        end
        set(lhnrm,'xdata',xdat,'ydata',Fv);
        drawnow;
    end
    
    if plotex
        ediff = E-Eex;
        if ediff<0,warning('variational energy is lower than exact energy');end
        dev = [dev;abs(ediff)];
        if plotvst
            tv = [tv;ttot];
            xdat = tv;
        else
            xdat = 1:length(dev);
        end
        set(lhex,'xdata',xdat,'ydata',dev);
        drawnow;
    end
    
    run_vumps = max(errs(:)) > thresh ||  max(F) > thresh || (any(mtoosmall) && any(lamtoobig));
end
end


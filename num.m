classdef num
  methods(Static)
     function out=cov(x,y)
      n=size(x,2);
      if n==0
        out=0;
        return
      end
      if any(size(x)~=size(y))
        out=Nan;
        return
      end
      out=size(1,n);
      for i=1:n
        out(i)=sum(...
          (x(:,i)-mean(x(:,i))).*...
          (y(:,i)-mean(y(:,i)))...
        )/size(x,1);
      end
    end
    function out=corrcoef(x,y)
      n=min([size(x,2),size(y,2)]);
      if n==0
        out=0;
        return
      end
      out=size(1,n);
      for i=1:n
        if any([std(x(:,i)),std(y(:,i))]==0)
          out(i)=0;
        else
          out(i)=num.cov(x(:,i),y(:,i))./std(x(:,i),1)./std(y(:,i),1);
        end
      end
    end
    function out=pardecomp(t,y,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired( 't', @(i) isnumeric(i) && isvector(i) && size(i,2)==1          && ~any(isnan(i)) );
      p.addRequired( 'y', @(i) isnumeric(i) && isvector(i) && all(size(i)==size(t)) && ~any(isnan(i)) );
      p.addParameter('polynomial',[0 1],                                     @(i) isnumeric(i) || isempty(i));
      p.addParameter('sinusoidal',seconds([2*min(diff(t)),(t(end)-t(1))/2]), @(i) isduration(i)|| isempty(i));
      p.addParameter('t0',        t(1),                                      @(i) isnumeric(i) && isscalar(i));
      p.addParameter('mode',      'struct',                                  @(i) ischar(i));
      %these parameters are only valid for the "model" mode.
      p.addParameter('x',         [],                                        @(i) isnumeric(i) || isempty(i));
      % parse it
      p.parse(t,y,varargin{:});
      %simpler names
      np=numel(p.Results.polynomial);
      ns=numel(p.Results.sinusoidal);
      ny=numel(y);
      %start from t0
      t=t-p.Results.t0;
      % trivial call
      if ~any(y~=0)
        %assign outputs
        out=struct(...
            'polynomial',zeros(np,1),...
            'sinusoidal',zeros(ns,1),...
          'cosinusoidal',zeros(ns,1),...
          'y_polynomial',zeros(ny,np),...
          'y_sinusoidal',zeros(ny,ns),...
        'y_cosinusoidal',zeros(ny,ns),...
          'y_res',zeros(ny,1),...
          'rnorm',0,...
          'norm',0 ...
        );
        %we're done
        return
      end
      % branch on mode
      switch p.Results.mode
        case 'test'
          s=1;
          n=1000;
          randn_scale=0.05;
          poly_scale=[0.3 0.8 1.6];
          T=s*n./[3 5];
          sin_scale=[0.8 0.5];
          cos_scale=[0.4 0.6]; 
          %derived parameters
          legend_str=cell(1,numel(poly_scale)+numel(sin_scale));
          t=transpose(1:s:(n*s));
          y=randn_scale*randn(n,1);c=0;
          for i=1:numel(poly_scale)
            c=c+1;legend_str{c}=['t^',num2str(i-1)];
            y=y+poly_scale(i)*(t/n/s).^(i-1);
          end
          for i=1:numel(sin_scale)
            c=c+1;legend_str{c}=['sin_',num2str(i)];
            y=y+sin_scale(i)*sin(2*pi/T(i)*t);
          end
          for i=1:numel(cos_scale)
            c=c+1;legend_str{c}=['cos_',num2str(i)];
            y=y+cos_scale(i)*cos(2*pi/T(i)*t);
          end
          %decompose
          a=num.pardecomp(t,y,'polynomial',ones(size(poly_scale)),'sinusoidal',T,'mode','struct');
          %show results
          figure
          plot(t,y,'b','LineWidth',2), hold on
          plot(t,a.y_polynomial,'r','LineWidth',2)
          plot(t,a.y_sinusoidal,'g','LineWidth',2)
          plot(t,a.y_cosinusoidal,'m','LineWidth',2)
          plot(t,a.y_res,'k','LineWidth',2)
          legend('original',legend_str{:},'res')
          title(['norm(x+res-y)=',num2str(norm(sum([a.y_polynomial,a.y_sinusoidal,a.y_cosinusoidal,a.y_res,-y],2))),...
            newline,'A=',num2str(a.amplitude(:)'),newline,'phi=',num2str(180/pi*a.phase(:)')])
          fs=16;
          set(    gca,          'FontSize',fs);
          set(get(gca,'Title' ),'FontSize',round(fs*1.3));
          set(get(gca,'XLabel'),'FontSize',round(fs*1.1));
          set(get(gca,'YLabel'),'FontSize',round(fs*1.2));
        case 'design'
          %convert to seconds and remove total time length
          %(only simpledata connects to this function, so time must be its implicit time scale, which is defined in simpletimeseries)
          T=simpletimeseries.timescale(p.Results.sinusoidal);
          % init design matrix
          A=zeros(ny,np+2*ns);
          % build design matrix: polynomial coefficients
          for i=1:np
            A(:,i)=t.^p.Results.polynomial(i);
          end
          % build design matrix: sinusoidal coefficients
          for i=np+(1:ns)
            A(:,i)=sin(2*pi/T(i-np)*t);
          end
          % build design matrix: co-sinusoidal coefficients
          for i=np+ns+(1:ns)
            A(:,i)=cos(2*pi/T(i-np-ns)*t);
          end
          %outputs
          out=A;
        case 'model'
          %sanity
          assert(~isempty(p.Results.x),[mfilename,': need input argument ''x''.'])
          %get the design matrix
          A=num.pardecomp(t,y,varargin{:},'mode','design');
          %get modelled components
          x=p.Results.x;
          y_mod=zeros(numel(y),numel(x));
          for j=1:numel(x)
            y_mod(:,j)=A(:,j)*x(j);
          end
          %outputs
          out=y_mod;
        case 'struct'
          %get the design matrix
          A=num.pardecomp(t,y,varargin{:},'mode','design');
          %solve the system of linear equations
          x=A\y;
          %get modelled components
          y_mod=num.pardecomp(t,y,varargin{:},'mode','model','x',x);
          %get residuals
          y_res=y-sum(y_mod,2);
          %assign outputs
          out=struct(...
            'polynomial',x(1:np),...
            'sinusoidal',x(np+1:np+ns),...
            'cosinusoidal',x(np+ns+1:end),...
            'y_polynomial',y_mod(:,1:np),...
            'y_sinusoidal',y_mod(:,np+1:np+ns),...
            'y_cosinusoidal',y_mod(:,np+ns+1:end),...
            'y_res',y_res,...
            'rnorm',norm(y_res)./norm(y),...
            'norm',norm(y_res)...
          );
      otherwise
        error([mfilename,': unknown output mode ''',p.Results.mode,'''.'])
      end
    end
    % shortcut for [s.field(:,column)]
    function out=struct_deal(s,field,line,column)
      if ~xor(isempty(line),isempty(column))
        error([mfilename,': (only) one of ''line'' or ''column'' must be empty.'])
      end
      if isempty(line)
        out=zeros(size(s(1).(field),1),numel(s));
        for i=1:numel(s)
          out(:,i)=s(i).(field)(:,column);
        end
      else
        out=zeros(numel(s),size(s(1).(field),2));
        for i=1:numel(s)
          out(i,:)=s(i).(field)(line,:);
        end
      end
    end
    % converts cell array to numeric array if all entries are numeric
    function inout=cell(inout)
      if iscell(inout) && all(cellfun(@isnumeric,inout))
        inout=cell2mat(inout);
      end
    end
    function out=odd(in)
      if mod(in,2)==0
        out=in-1;
      else
        out=in;
      end
    end
    function x_opt=param_search1(fun,x,varargin)
      % input parsing
      p=inputParser; p.KeepUnmatched=true;
      p.addRequired( 'fun',                   @(i) isa(i,'function_handle'));
      p.addRequired( 'xrange',                @(i) isnumeric(i));
      p.addParameter('searchspace', 'linear', @(i) ischar(i));
      p.addParameter('searchlen',numel(x)*10, @(i) isnumeric(i));
      p.addParameter('interpmethod','spline', @(i) ischar(i));
      p.addParameter('plot',           false, @(i) islogical(i));
      p.addParameter('enforce_scalar', false, @(i) islogical(i));
      p.addParameter('vectorize',     false, @(i) islogical(i));
      p.parse(fun,x,varargin{:})
      %define search space
      switch p.Results.searchspace
      case {'linear'}
        xd=linspace(x(1),x(end),p.Results.searchlen);
      case {'log'}
        xd=logspace(log10(x(1)),log10(x(end)),p.Results.searchlen);
      otherwise
        error(['Cannot handle argument ''searchspace'' with value ''',p.Results.searchspace,'''.'])
      end
      %use vectorize if allowed
      if p.Results.vectorize
        y=fun(x);
      else
        %init records
        y=nan(size(x));
        %loop over xrange
        for i=1:numel(x)
          y(i)=fun(x(i));
        end
      end
      %interpolate
      yd=interp1(x,y,xd,p.Results.interpmethod);
      %pick the minimum
      yi=yd==min(yd);
      x_opt=xd(yi);
      %warn user if minimum is at one extremety
      if yi(1) || yi(end)
        warning(['Could not find minimum of function ''',func2str(fun),''' in [',num2str(x(1)),',',num2str(x(end)),']'])
      end
      if p.Results.enforce_scalar
        x_opt=x_opt(1);
      end
      %debug plot
      if p.Results.plot
        figure
        plot(x_opt,yd(yi),'*','Markersize',10), hold on
        plot(x,y,'o')
        plot(xd,yd,'-')
        set(gca,'XScale',p.Results.searchspace)
        legend({'minimum','tries','interpolated'})
      end
    end
    function [x_opt,y,x]=param_brute(fun,x_lower,x_upper,varargin)
      % input parsing
      p=inputParser; p.KeepUnmatched=true;
      p.addRequired( 'fun',                   @(i) isa(i,'function_handle'));
      p.addRequired( 'x_upper',               @(i) isnumeric(i));
      p.addRequired( 'x_lower',               @(i) isnumeric(i));
      p.addParameter('searchspace', 'linear', @(i) ischar(i));
      p.addParameter('searchlen',        100, @(i) isnumeric(i));
      p.addParameter('searchlenmaxfactor',2e10,@(i) isnumeric(i));
      p.addParameter('searchiter',         0, @(i) isnumeric(i));
      p.addParameter('searchiter_counter', 0, @(i) isnumeric(i));
      p.addParameter('searchpdf',     'rand', @(i) ischar(i));
      p.addParameter('searchshrinkfactor', 2, @(i) isnumeric(i));
      p.addParameter('vectorize',      false, @(i) islogical(i));
      p.parse(fun,x_upper,x_lower,varargin{:})
      %sanity
      assert(numel(x_upper)==numel(x_lower),...
        'Arguments ''x0'', ''x_upper'' and ''x_lower'' must have the same number of elements')
      %simpler names
      l=p.Results.searchlen;
      n=numel(x_upper);
      searchpdf=str2func(p.Results.searchpdf);
      %define search space
      switch p.Results.searchspace
      case {'linear'}
        d0=x_lower;
        dx=x_upper-d0;
        x=searchpdf(l,n).*(ones(l,1)*dx)+ones(l,1)*d0;
      case {'log'}
        d0=log10(x_lower);
        dx=log10(x_upper)-d0;
        x=10.^(searchpdf(l,n).*(ones(l,1)*dx)+ones(l,1)*d0);
      otherwise
        error(['Cannot handle argument ''searchspace'' with value ''',p.Results.searchspace,'''.'])
      end
      %limit the search length: get an estimate of the memory used by fun
      fun_info=functions(fun);
      fun_mem=sum(structfun(@(i) numel(i),fun_info.workspace{1}));
      if l*fun_mem^2>p.Results.searchlenmaxfactor
        l_old=l;
        l=floor(p.Results.searchlenmaxfactor/fun_mem^2);
        str.say('stack_delta',1,['searchlen reset to ',num2str(l),...
          ' because searchlen*fun_mem>searchlenmaxfactor (',...
          num2str(l_old),'*',num2str(fun_mem),'>',num2str(p.Results.searchlenmaxfactor),')'])
      end
      %use vectorize if allowed
      if p.Results.vectorize
        y=fun(x);
      else
        %init records
        y=nan(size(x,1),1);
        %loop over xrange
        for i=1:size(x,1)
          y(i)=fun(x(i,:));
        end
      end
      assert(~any(isnan(y)),'Found NaNs in the output of fun')
      %retrieve lowest value from all y and get corresponding x
      x_opt=x(find(min(y)==y,1,'first'),:);
      %iterate if requested
      if p.Results.searchiter>0
        sd=1+p.Results.searchiter_counter;
        str.say('stack_delta',sd,str.tablify(16,'----- iter ----- ',p.Results.searchiter_counter+1))
        str.say('stack_delta',sd,str.tablify(16,'res',min(y)))
        str.say('stack_delta',sd,str.tablify(16,'res',min(y)))
        str.say('stack_delta',sd,str.tablify(16,'x_lower',x_lower))
        str.say('stack_delta',sd,str.tablify(16,'x_opt',x_opt))
        str.say('stack_delta',sd,str.tablify(16,'x_upper',x_upper))
        if p.Results.searchiter_counter<=p.Results.searchiter
          %define next iter search space amplitude
          dx=dx/p.Results.searchshrinkfactor;
          %define next iter search space
          switch p.Results.searchspace
          case {'linear'}
            x_lower=x_opt-dx/2;
            x_upper=x_opt+dx/2;
          case {'log'}
            x_lower=x_opt./10.^(dx/2);
            x_upper=x_opt.*10.^(dx/2);
          otherwise
            error(['Cannot handle argument ''searchspace'' with value ''',p.Results.searchspace,'''.'])
          end
          %iteration number
          iter=p.Results.searchiter_counter+1;
          %recursive call
          [~,y_iter,x_iter]=num.param_brute(fun,...
            x_lower,...
            x_upper,...
            varargin{:},...
            'searchlen',l,...
            'searchiter_counter',iter ...
          );
          %append to existing set of y,x
          y=[y(:);y_iter(:)];x=[x;x_iter];
          %update lowest value from all y and get corresponding x (may be the same)
          x_opt=x(find(min(y)==y,1,'first'),:);
        end
      end
    end
    %% memory utils (everything is in Mb)
    function out=memory_system
      if ismac
        com='sysctl hw.memsize';
        [status, cmdout]=system(com);
        if status; error(['could not issue the command ''',com,'''; debug needed.']);end
        cmdout=cells.rm_empty(strsplit(cmdout));
        out=str2double(cmdout{2})/1024^2;
      elseif isunis
        error('implementation needed')
      elseif ispc
        error('implementation needed')
      else
        error('cannot determine the operating system type')
      end
      if isnan(out);keyboard;end
    end
    function out=memory_matlab_fraction
      if ismac
        com='ps -c -o ''pmem comm'' | grep maci64';
        [status, cmdout]=system(com);
        if status; error(['could not issue the command ''',com,'''; debug needed.']);end
        cmdout=cells.rm_empty(strsplit(cmdout));
        out=str2double(cmdout{1})/100;
      elseif isunis
        error('implementation needed')
      elseif ispc
        error('implementation needed')
      else
        error('cannot determine the operating system type')
      end
      if isnan(out);keyboard;end
    end
    %% statistics
    function out = rms(x,w,dim)
      if ~exist('dim','var') || isempty(dim)
        dim=0;
      else
        assert(dim <= numel(size(w)),'the value of input <dim> must not be larger than the number of dimensions in <x>')
      end
      if ~exist('w','var') || isempty(w)
        w=ones(size(x));
      else
        assert(all(size(w) == size(x)),'inputs <x> and <w> must have the same size')
      end
      switch dim
      case 0
        %filtering NaNs
        i = ~isnan(x) & ~isnan(w);
        %compute
        out= sqrt(sum(w(i).*(x(i).^2))/sum(w(i)));
      case 1 %computes the RMS along columns, so a row is returned
        out=arrayfun(@(i) num.rms(x(:,i),w(:,i),0),1:size(x,2));
      case 2 %computes the RMS along rows, so a column is returned
        out=transpose(arrayfun(@(i) num.rms(x(i,:),w(i,:),0),1:size(x,1)));
      otherwise
        error(['dim=',num2str(dim),' not implemented.'])
      end
    end
  end
end
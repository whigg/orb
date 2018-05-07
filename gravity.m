classdef gravity < simpletimeseries
  %static
  properties(Constant)
    %this is used to define when the date is not set (datenum(zero_date)=0), used for static fields
    zero_date=time.zero_date;
%   Supported functionals are the following,
%       'nondim'    - non-dimensional Stoked coefficients.
%       'eqwh'      - equivalent water height [m]
%       'geoid'     - geoid height [m]
%       'potential' - [m2/s2]
%       'gravity'   - [m /s2], if input represents the disturbing potential,
%                     then the output represents the gravity disturbances.
%                     Otherwise, it represents the gravity accelerations
%                     (-dU/dr).
%       'anomalies' - If input represents the disturbing potential, then
%                     the output represents the gravity anomalies.
%                     Otherwise, it represents (-dU/dr - 2/r*U).
%       'vertgravgrad' - vertical gravity gradient.
    functional_details=struct(...
      'nondim',        struct('units',' ',         'name','Stokes Coeff.'),...
      'eqwh',          struct('units','m',         'name','Eq. Water Height'),...
      'geoid',         struct('units','m',         'name','Geoid Height'),...
      'potential',     struct('units','m^2.s^{-2}','name','Geopotential'),...
      'anomalies',     struct('units','m.s^{-2}',  'name','Gravity Anomalies'),...
      'vertgravgrad',  struct('units','s^{-2}',    'name','Vert. Gravity Gradient'),...
      'gravity',       struct('units','m.s^{-2}',  'name','Gravity Acc.')...
    );
    %default value of some internal parameters
    parameter_list={...
      'G',        6.67408e-11,   @(i) isnumeric(i) && isscalar(i);...      % Gravitational constant [m3/kg/s2]
      'GM',       398600.4415e9, @(i) isnumeric(i) && isscalar(i);...      % Standard gravitational parameter [m^3 s^-2]
      'R',        6378136.460,   @(i) isnumeric(i) && isscalar(i);...      % Earth's equatorial radius [m]
      'Rm',       6371000,       @(i) isnumeric(i) && isscalar(i);...      % Earth's mean radius [m]
      'rho_earth',5514.3231,     @(i) isnumeric(i) && isscalar(i);...      % average density of the Earth = (GM/G) / (4/3*pi*R_av^3) [kg/m3]
      'rho_water',1000,          @(i) isnumeric(i) && isscalar(i);...      % water density
      'love',  [  0       0.000;...   
                  1       0.027;...
                  2      -0.303;...
                  3      -0.194;...
                  4      -0.132;...
                  5      -0.104;...
                  6      -0.089;...
                  7      -0.081;...
                  8      -0.076;...
                  9      -0.072;...
                  10     -0.069;...
                  12     -0.064;...
                  15     -0.058;...
                  20     -0.051;...
                  30     -0.040;...
                  40     -0.033;...
                  50     -0.027;...
                  70     -0.020;...
                  100    -0.014;...
                  150    -0.010;...
                  200    -0.007], @(i) isnumeric(i) && size(i,2)==2;...     % Love numbers
        'origin',      'unknown', @(i) ischar(i);...                        % (arbitrary string)
        'functional',   'nondim', @(i) ischar(i) && any(strcmp(i,gravity.functionals)); %see above
    };
    %These parameter are considered when checking if two data sets are
    %compatible (and only these).
    %NOTE: edit this if you add a new parameter (if relevant)
    compatible_parameter_list={'GM','R','functional','lmax'};
  end
  %read only
  properties(SetAccess=public)
    GM
    R
    functional
    origin
  end
  %calculated only when asked for
  properties(Dependent)
    lmax
    mat
    cs
    tri
    mod
    checksum
    funct %handles empty values of functional
  end
  methods(Static)
    function out=parameters(i,method)
      persistent v parameter_names
      if isempty(v)
        v=varargs(gravity.parameter_list);
        parameter_names=v.Parameters;
      end
      if ~exist('i','var') || isempty(i)
        if ~exist('method','var') || isempty(method)
          out=parameter_names(:);
        else
          switch method
          case 'obj'
            out=v;
          otherwise
            out=v.(method);
          end
        end
      else
        if ~exist('method','var') || isempty(method)
          method='name';
        end
        if strcmp(method,'name') && isnumeric(i)
          out=parameter_names{i};
        else
          switch method
          case varargs.template_fields
            out=v.get(i).(method);
          otherwise
            out=v.(method);
          end
        end
      end
    end
    function out=issquare(in)
      in_sqrt=sqrt(in);
      out=(in_sqrt-round(in_sqrt)==0);
    end
    function out=functionals
      out=fieldnames(gravity.functional_details);
    end
    function out=functional_units(functional)
      assert(gravity.isfunctional(functional),['Ilegal functional ''',functional,'''.'])
      out=gravity.functional_details.(functional).units;
    end
    function out=functional_names(functional)
      assert(gravity.isfunctional(functional),['Ilegal functional ''',functional,'''.'])
      out=gravity.functional_details.(functional).name;
    end
    function out=functional_label(functional)
      out=[gravity.functional_names(functional),' [',gravity.functional_units(functional),']'];
    end
    function out=isfunctional(in)
      out=isfield(gravity.functional_details,in);
    end
    %% y representation
    function out=y_valid(y)
      out=size(y,1)==1 && gravity.issquare(numel(y));
    end
    function lmax=y_lmax(y)
      lmax=sqrt(numel(y))-1;
    end
    function s=y_length(lmax)
      s=(lmax+1).^2;
    end
    %% mat representation
    function out=mat_valid(mat)
      out=size(mat,1)==size(mat,2);
    end
    function lmax=mat_lmax(mat)
      lmax=gravity.y_lmax(mat(:));
    end
    function s=mat_length(lmax)
      s=[lmax+1,lmax+1];
    end
    %% cs representation
    function out=cs_valid(in)
      out=isfield(in,'C') && isfield(in,'S');
      if ~out,return,end
      z=triu(in.C,1)+triu([in.S(:,2:end),zeros(size(in.C,1),1)],0);
      out=all(size(in.C)==size(in.S)) && size(in.C,1) == size(in.C,2) && all(z(:)==0) ;
    end
    function lmax=cs_lmax(cs)
      lmax=gravity.y_lmax(cs.C(:));
    end
    function s=cs_length(lmax)
      s=gravity.mat_length(lmax);
    end
    %% tri representation
    function out=tri_valid(tri)
      lmax=gravity.tri_lmax(tri);
      out=size(tri,1)==lmax+1 && round(lmax)==lmax && gravity.cs_valid(gravity.tri2cs(tri));
    end
    function lmax=tri_lmax(tri)
      lmax=(size(tri,2)+1)/2-1;
    end
    function s=tri_length(lmax)
      s1=gravity.mat_length(lmax);
      s=[s1(1),2*(lmax+1)-1];
    end
    %% mod representation
    function out=mod_valid(mod)
      n=gravity.mod_lmax(mod)+1;
      out=size(mod,2)==4 && size(mod,1)==n*(n+1)/2;
    end
    function lmax=mod_lmax(mod)
      lmax=max(mod(:,1));
    end
    function s=mod_length(lmax)
      s=[(lmax*(lmax+1))/2,2*(lmax+1)-1];
    end
    %% y and mat convertions
    function mat=y2mat(y)
      mat=zeros(sqrt(numel(y)));
      mat(:)=y;
    end
    function y=mat2y(mat)
      y=transpose(mat(:));
    end
    %% cs and mat convertions
    function cs=mat2cs(mat)
      S=transpose(triu(mat,1));
      cs=struct(...
        'C',tril(mat,0),...
        'S',[zeros(size(mat,1),1),S(:,1:end-1)]...
      );
    end
    function mat=cs2mat(cs)
      mat=cs.C+transpose([cs.S(:,2:end),zeros(size(cs.C,1),1)]);
    end
    %% cs and tri convertions
    function tri=cs2tri(cs)
      tri=[fliplr(cs.S(:,2:end)),cs.C];
    end
    function cs=tri2cs(tri)
      n=(size(tri,2)+1)/2;
      cs=struct(...
        'S',[zeros(n,1),fliplr(tri(:,1:n-1))],...
        'C',tri(:,n:end)...
      );
    end
    %% cs and mod convertions
    function mod=cs2mod(in)
      %shortcuts
      n=size(in.C,1);
      %create lower triangle index matrix
      idxm=zeros(n);
      idxm(:)=1:n*n;
      idxm(idxm==triu(idxm,1))=NaN;
      %create index list
      [d,o]=ind2sub(n,idxm(:));
      %get location of NaNs
      i=isnan(d);
      %flatten coefficients
      C=in.C(:);S=in.S(:);
      %filter out upper diagonals
      d(i)=[];
      o(i)=[];
      C(i)=[];
      S(i)=[];
      %assemble
      mod=[d-1,o-1,C,S];
    end
    function out=mod2cs(mod)
      %shortcuts
      n=gravity.mod_lmax(mod)+1;
      %create lower triangle index matrix
      idxm=zeros(n);
      idxm(:)=1:n*n;
      %make room
      out=struct(...
        'C',zeros(max(mod(:,1))+1),...
        'S',zeros(max(mod(:,1))+1)...
      );
      %propagate
      out.C(idxm==tril(idxm, 0)) = mod(:,3);
      out.S(idxm==tril(idxm, 0)) = mod(:,4);
      %assing outputs
    end
    %% agregator routines
    %data type converter
    function out=dtc(from,to,in)
      %trivial call
      if strcmpi(from,to)
        out=in;
        return
      end
      %check input
      if ~gravity.dtv(from,in)
        error([mfilename,': invalid data of type ''',from,'''.'])
      end
      %convert to required types
      switch lower(from)
        case 'y'
          switch lower(to)
            case 'mat'; out=gravity.y2mat(in);
            case 'cs';  out=gravity.mat2cs(gravity.y2mat(in));
            case 'tri'; out=gravity.cs2tri(gravity.mat2cs(gravity.y2mat(in)));
            case 'mod'; out=gravity.cs2mod(gravity.mat2cs(gravity.y2mat(in)));
          end
        case 'mat'
          switch lower(to)
            case 'y';   out=gravity.mat2y(in);
            case 'cs';  out=gravity.mat2cs(in);
            case 'tri'; out=gravity.cs2tri(gravity.mat2cs(in));
            case 'mod'; out=gravity.cs2mod(gravity.mat2cs(in));
          end
        case 'cs'
          switch lower(to)
            case 'y';   out=gravity.mat2y(gravity.cs2mat(in));
            case 'mat'; out=gravity.cs2mat(in);
            case 'tri'; out=gravity.cs2tri(in);
            case 'mod'; out=gravity.cs2mod(in);
          end
        case 'tri'
          switch lower(to)
            case 'y';   out=gravity.mat2y(gravity.cs2mat(gravity.tri2cs(in)));
            case 'mat'; out=gravity.cs2mat(gravity.tri2cs(in));
            case 'cs';  out=gravity.tri2cs(in);
            case 'mod'; out=gravity.cs2mod(gravity.tri2cs(in));
          end
        case 'mod'
          switch lower(to)
            case 'y';   out=gravity.mat2y(gravity.cs2mat(gravity.mod2cs(in)));
            case 'mat'; out=gravity.cs2mat(gravity.mod2cs(in));
            case 'cs';  out=gravity.mod2cs(in);
            case 'tri'; out=gravity.cs2tri(gravity.mod2cs(in));
          end
      end
    end
    %data type validity
    function c=dtv(type,in)
      switch lower(type)
      case 'y';  c=gravity.y_valid(in);
      case 'mat';c=gravity.mat_valid(in);
      case 'cs'; c=gravity.cs_valid(in);
      case 'tri';c=gravity.tri_valid(in);
      case 'mod';c=gravity.mod_valid(in);
      otherwise
        error([mfilename,': unknown data type ''',from,'''.'])
      end
    end
    %data type lmax
    function c=dtlmax(type,in)
      switch lower(type)
      case 'y';  c=gravity.y_lmax(in);
      case 'mat';c=gravity.mat_lmax(in);
      case 'cs'; c=gravity.cs_lmax(in);
      case 'tri';c=gravity.tri_lmax(in);
      case 'mod';c=gravity.mod_lmax(in);
      otherwise
        error([mfilename,': unknown data type ''',from,'''.'])
      end
    end
    %data type length
    function s=dtlength(type,in)
      switch lower(type)
      case 'y';  s=gravity.y_length(in);
      case 'mat';s=gravity.mat_length(in);
      case 'cs'; s=gravity.cs_length(in);
      case 'tri';s=gravity.tri_length(in);
      case 'mod';s=gravity.mod_length(in);
      otherwise
        error([mfilename,': unknown data type ''',from,'''.'])
      end
    end
    %% degree/order index mapping
    function out=mapping(lmax)
      %create triangular matrix for degrees
      d=(0:lmax)'*ones(1,2*lmax+1).*gravity.dtc('mat','tri',ones(lmax+1));
      %create triangular matrix for orders
      o=ones(lmax+1,1)*(-lmax:lmax).*gravity.dtc('mat','tri',ones(lmax+1));
      %convert to vector
      d=gravity.dtc('tri','y',d);
      o=gravity.dtc('tri','y',o);
      out=[d;o];
    end
    function [l,u]=labels(lmax,units_str)
      map=gravity.mapping(lmax);
      l=cell(1,size(map,1));
      for i=1:size(map,2)
        l{i}=['C',num2str(map(1,i)),',',num2str(map(2,i))];
      end
      if nargin>1 && nargout>1
        u=cell(size(l));
        u(:)={units_str};
      end
    end
    function out=colidx(d,o,lmax)
      if any(size(d)~=size(o))
        error([mfilename,': inputs ''d'' and ''o'' must have the same size(s).'])
      end
      m=gravity.mapping(lmax);
      out=false(1,size(m,2));
      for i=1:numel(d)
        out=out | (m(1,:)==d(i) & m(2,:)==o(i));
      end
      out=find(out);
    end
    %% constructors
    function obj=unit(lmax,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired( 'lmax',                            @(i) isscalar(i) && isnumeric(i));
      p.addParameter('scale',           1,              @(i) isscalar(i));
      p.addParameter('scale_per_degree',ones(lmax+1,1), @(i) isvector(i) && lmax+1 == numel(i));
      p.addParameter('scale_per_coeff', ones(lmax+1),   @(i) ismatrix(i) && all([lmax+1,lmax+1] == size(i)));
      p.addParameter('t',               datetime('now'),@(i) isdatetime(i) || isvector(i));
      %create argument object, declare and parse parameters, save them to obj
      [v,p]=varargs.wrap('parser',p,'sources',{gravity.parameters([],'obj')},'mandatory',{lmax},varargin{:});
      %create unitary triangular matrix
      u=gravity.dtc('mat','tri',ones(lmax+1));
      %scale along degrees (if needed)
      if any(p.Results.scale_per_degree(:)~=1)
        u=p.Results.scale_per_degree(:)*ones(1,size(u,2)).*u;
      end
      %scale per coefficient (if needed)
      if any(p.Results.scale_per_coeff(:)~=1)
        u=gravity.dtc('mat','tri',p.Results.scale_per_coeff).*u;
      end
      %replicate by the nr of elements of t
      u=ones(numel(p.Results.t),1)*gravity.dtc('tri','y',u);
      %initialize
      varargin_now=cells.vararginclean(varargin,{'t'});
      obj=gravity(p.Results.t,u,varargin_now{:});
      % save the arguments v into this object
      obj=v.save(obj);
      %call upstream scale method for global scale
      obj=obj.scale(p.Results.scale);
    end
    % creates a unit model with per-degree amplitude equal to 1
    function obj=unit_amplitude(lmax,varargin)
      obj=gravity.unit(lmax,'scale_per_degree',1./sqrt(2*(0:lmax)+1),varargin{:});
    end
    % creates a unit model with per-degree RMS equal to 1
    function obj=unit_rms(lmax,varargin)
      obj=gravity.unit(lmax,'scale_per_degree',gravity.unit(lmax).drms,varargin{:});
    end
    % Creates a random model with mean 0 and std 1 (per degree)
    function obj=unit_randn(lmax,varargin)
      obj=gravity.unit(lmax,'scale_per_coeff',randn(lmax+1),varargin{:});
    end
    function obj=nan(lmax,varargin)
      obj=gravity.unit(lmax,'scale',nan,varargin{:});
    end
    function [m,e]=load(filename,fmt,time)
      %default type
      if ~exist('fmt','var') || isempty(fmt)
        [~,fn,fmt]=fileparts(filename);
        %get rid of the dot
        fmt=fmt(2:end);
        %check if this is CSR format
        if strcmp(fn,'GEO')
          fmt='csr';
        end
      end
      %default time
      if ~exist('time','var') || isempty(time)
        time=datetime('now');
      end
      %handle mat files
      [~,~,ext]=fileparts(filename);
      if strcmp(ext,'.mat')
        mat_filename=filename;
        filename=strrep(filename,'.mat','');
      else
        mat_filename=[filename,'.mat'];
      end
      %check if mat file is already available
      if isempty(dir(mat_filename))
        switch lower(fmt)
        case 'gsm'
          [m,e]=load_gsm(filename,time);
        case 'csr'
          [m,e]=load_csr(filename,time);
        case {'icgem','gfc'}
          [m,e]=load_icgem(filename,time);
        case 'mod'
          [m,e]=load_mod(filename,time);
        otherwise
          error([mfilename,': cannot handle models of type ''',fmt,'''.'])
        end
        save(mat_filename,'m','e')
      else
        %NOTICE: input argument 'time' is ignored here; only by coincidence (or design,
        %        e.g. if gravity.load_dir is used) will time be same as the one saved
        %        in the mat file.
        load(mat_filename)
        %enforce input 'time'
        if m.t~=time;m.t=time;end %#ok<NODEF>
        if e.t~=time;e.t=time;end %#ok<NODEF>
      end
    end
    function out=parse_epoch_grace(filename)
      [~,f]=fileparts(filename);
      %GSM-2_2015180-2015212_0027_JPLEM_0001_0005.gsm
      %123456789012345678901234567890
      start=dateshift(...
        time.doy2datetime(...
          str2double(f(7 :10)),...
          str2double(f(11:13))...
        ),...
      'start','day');
      stop =dateshift(...
        time.doy2datetime(...
          str2double(f(15:18)),...
          str2double(f(19:21))...
        ),...
      'end','day');
      out=mean([start,stop]);
    end
    function out=parse_epoch_aiub(filename)
      [~,f]=fileparts(filename);
      %AIUB_swarmABC_201312_70x70.gfc
      %123456789012345678901234567890
      start=dateshift(datetime([f(15:18),'-',f(19:20),'-01']),'start','month');
      stop =dateshift(datetime([f(15:18),'-',f(19:20),'-01']),'end',  'month');
      out=mean([start,stop]);
    end
    function out=parse_epoch_aiub_slr(filename)
      [~,f]=fileparts(filename);
      %AIUB-SLR_0301_1010.gfc
      %123456789012345678901234567890
      start=dateshift(datetime(['20',f(10:11),'-',f(12:13),'-01']),'start','month');
      stop =dateshift(datetime(['20',f(10:11),'-',f(12:13),'-01']),'end',  'month');
      out=mean([start,stop]);
    end
    function out=parse_epoch_asu(filename)
      [~,f]=fileparts(filename);
      %asu-swarm-2014-10-nmax40-orbits-aiub.gfc
      %123456789012345678901234567890
      start=dateshift(datetime([f(11:14),'-',f(16:17),'-01']),'start','month');
      stop =dateshift(datetime([f(11:14),'-',f(16:17),'-01']),'end',  'month');
      out=mean([start,stop]);
    end
    function out=parse_epoch_ifg(filename)
      [~,f]=fileparts(filename);
      %coeff-2015-03-SaSbSc-AIUB.gfc
      %123456789012345678901234567890
      start=dateshift(datetime([f(07:10),'-',f(12:13),'-01']),'start','month');
      stop =dateshift(datetime([f(07:10),'-',f(12:13),'-01']),'end',  'month');
      out=mean([start,stop]);
    end
    function out=parse_epoch_csr(filename)
      %2016-11.GEO.716424
      %12345678901234567890
      [~,file]=fileparts(filename);
      year =str2double(file(1:4));
      month=str2double(file(6:7));
      out=gravity.CSR_RL05_date(year,month);
    end
    function out=parse_epoch_gswarm(filename)
      [~,file]=fileparts(filename);
      persistent kv
      if isempty(kv)
      %GSWARM_GF_SABC_COMBINED_2014-11_01.gfc
      %0000000001111111111222222222233333333334
      %1234567890123456789012345678901234567890
        kv={...
          'COMBINED',25;...
          'AIUB',    21;...
          'ASU',     20;...
          'IFG',     20;...
        };
      end
      idx=0;
      for i=1:size(kv,1)
        if strcmp(file(16:16+length(kv{i,1})-1),kv{i,1})
          idx=kv{i,2}; break
        end
      end
      assert(idx>0,['Cannot find any of the keywords ''',strjoin(kv(:,1),''', '''),''' in the filename ''',filename,'''.'])
      year =str2double(file(idx  :idx+3));
      month=str2double(file(idx+5:idx+6));
      out=datetime(year,month,1);
      out=out+(dateshift(out,'end','month')-out)/2;
    end
    function [m,e]=load_dir(dirname,format,date_parser,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired( 'dirname',     @(i) ischar(i));
      p.addRequired( 'format',      @(i) ischar(i));
      p.addRequired( 'date_parser', @(i) isa(i,'function_handle'));
      p.addParameter('wilcarded_filename',['*.',format], @(i) ischar(i))
      p.addParameter('descriptor',        'unknown',     @(i) ischar(i))
      p.addParameter('start', [], @(i) isempty(i) || (isdatetime(i)  &&  isscalar(i)));
      p.addParameter('stop',  [], @(i) isempty(i) || (isdatetime(i)  &&  isscalar(i)));
      p.parse(dirname,format,date_parser,varargin{:})
      %retrieve all gsm files in the specified dir
      filelist=file.unwrap(fullfile(dirname,p.Results.wilcarded_filename));
      %this counter is needed to report the duplicate models correctly
      c=0;init_flag=true;
      %loop over all models
      for i=1:numel(filelist)
        %get time of the model in this file
        if strcmpi(func2str(p.Results.date_parser),'static')
          %if a static field is requested, there should be only one file
          if numel(filelist)~= 1
            error([mfilename,': when requested a static field, can only handle a single file, not ',...
              num2str(numel(filelist)),'.'])
          end
          %patch missing start epoch (static fields have no epoch)
          t=gravity.zero_date;
        else
          t=p.Results.date_parser(filelist{i});
          %skip if this t is outside the required range
          if time.isvalid(p.Results.start) && time.isvalid(p.Results.stop) && (t<p.Results.start || p.Results.stop<t)
            c=c+1;
            continue
          end
        end
        %user feedback
        [~,f]=fileparts(filelist{i});
        disp(['Loading  ',f,' (to date ',datestr(t),')'])
        %load the data
        if init_flag
          %init output objects
          [m,e]=gravity.load(filelist{i},p.Results.format,t);
          %init no more
          init_flag=false;
        else
          %use temp container
          [m1,e1]=gravity.load(filelist{i},p.Results.format,t);
          %check if there are multiple models defined at the same epoch
          if m.istavail(m1.t)
            %find the model with the same epoch that has already been loaded
            [~,f_saved  ]=fileparts(filelist{m.idx(m1.t)+c});
            disp(['Ignoring ',f,' because this epoch was already loaded from model ',f_saved,'.'])
            c=c+1;
          else
            %ensure R and GM are compatible
            m1=m1.scale(m);
            e1=e1.scale(e);
            %append to output objects
            m=m.append(m1);
            e=e.append(e1);
          end
        end
      end
      %fix some parameters
      m.origin=dirname;
      e.origin=dirname;
      m.descriptor=p.Results.descriptor;
      e.descriptor=['error of ',p.Results.descriptor];
    end
    %% retrieves the Monthly estimates of C20 from 5 SLR satellites based on GRACE RL05 models
    function out=graceC20(varargin)
      %call mother routine
      [t,s,e]=GetGraceC20(varargin{:});
      %create time series
      out=simpletimeseries(t,[s,e],...
        'labels',{'C20','error C20'},...
        'units',{'',''},...
        'timesystem','gps',...
        'descriptor','Monthly estimates of C20 from 5 SLR satellites based on GRACE RL05 models'...
      );
    end
    %% vector operations to make models compatible
    function lmax=vlmax(model_list)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired( 'model_list', @(i) iscell(i) && all(cellfun(isa(i,'gravity'))))
      p.parse(model_list)
      lmax=min(cell2mat(cellfun(@(i) i.lmax,model_list)));
    end
    function gm=vGM(model_list)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired( 'model_list', @(i) iscell(i) && all(cellfun(isa(i,'gravity'))))
      p.parse(model_list)
      gm=min(cell2mat(cellfun(@(i) i.GM,model_list)));
    end
    function r=vR(model_list)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired( 'model_list', @(i) iscell(i) && all(cellfun(isa(i,'gravity'))))
      p.parse(model_list)
      r=min(cell2mat(cellfun(@(i) i.R,model_list)));
    end
    %% model combination
    function out=combine(model_list,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired( 'model_list', @(i) iscell(i) && all(cellfun(@(i) isa(i,'gravity'),model_list)))
      p.addParameter('mode','mean',@(i) ischar(i))
      p.addParameter('type','signal',@(i) ischar(i))
      p.addParameter('weights',ones(size(model_list))/numel(model_list),@(i) isnumeric(i) && all(size(model_list)==size(i)))
      p.parse(model_list,varargin{:})
      %trivial call
      if numel(model_list)==1
        out=model_list;
      end
%       %sanity
%       for i=2:numel(model_list)
%         if ~model_list{1}.isteq(model_list{i})
%           error([mfilename,': time domain discrepancy between model ',...
%             model_list{1}.descriptor,' and model ',...
%             model_list{i}.descriptor,'.'])
%         end
%       end
      %set model compatibility
      model_list=simpledata.merge_multiple(model_list);
      %branch on mode
      switch lower(p.Results.mode)
      case {'mean','am','arithmeticmean'}
        switch lower(p.Results.type)
        case 'signal'
          out=simpledata.vmean(...
            model_list,...
          'weights',p.Results.weights);
        case 'error'
          out=simpledata.vmean(...
            simpledata.vtimes(model_list,model_list),...
          'weights',p.Results.weights).sqrt;
        otherwise
          error([mfilename,': unknown type ',p.Results.type,'.'])
        end
      case {'dtm','difftomean'}
        error([mfilename,': implementation needed'])
      otherwise
        error([mfilename,': unknown mode ''',p.Results.mode,'''.'])
      end
      %update the descriptor
      msg=cell(size(model_list));
      for i=1:numel(model_list)
        msg{i}=model_list{i}.descriptor;
      end
      out.descriptor=[p.Results.mode,' of ',strjoin(msg,', ')];
    end
    %% (half) wavelength to degree convertions
    function deg=wl2deg(wl)
      deg=2*pi*gravity.parameters('R','value')./wl;
    end
    function wl=deg2wl(deg)
      wl=gravity.wl2deg(deg);
    end
    function deg=hwl2deg(hwl)
      deg=gravity.wl2deg(hwl*2);
    end
    function hwl=deg2hwl(deg)
      hwl=gravity.deg2wl(deg)/2;
    end
    function rad=gauss_smoothing_radius(deg)
      rad=gravity.deg2hwl(deg)/2;
    end
    function deg=gauss_smoothing_degree(rad)
      deg=round(gravity.hwl2deg(rad*2));
    end
    function out=gauss_smoothing_type(in)
      % This is a weak criteria but will work as long as there's no need
      % to smooth at degrees larger than 10000 or radii smaller than 10km.
      if in>10e3;
        out='rad';
      else
        out='deg';
      end      
    end
    function out=gauss_smoothing_degree_translate(in)
      switch gravity.gauss_smoothing_type(in)
      case 'rad'; out=gravity.gauss_smoothing_degree(in);
      case 'deg'; out=in;
      end
    end
    function out=gauss_smoothing_name(in)
      switch gravity.gauss_smoothing_type(in)
      case 'rad'; out=[num2str(in/1e3),'km'];
      case 'deg'; out=[num2str(round(gravity.gauss_smoothing_radius(in)/1e4)*1e1),'km'];
      end
    end
    function out=smoothing_name(in)
      switch lower(in)
      case 'gauss';  out='Gaussian';
      case 'spline'; out='Spline';
      case 'trunc';  out='Truncation';
      otherwise; error(['Cannot handle smoothing method ''',in,'''.'])
      end
    end
    %% CSR specific stuff
    function t=CSR_RL05_date(year,month,varargin)
      p=inputParser; p.KeepUnmatched=true;
      p.addParameter('EstimDirs_file',fullfile(getenv('HOME'),'data','csr','EstimData','RL05','EstimDirs_RL05'),@(i) ischar(i))
      p.parse(varargin{:})
      %sanity on year
      if year<1000
        year=year+2000;
      end
      persistent CSR_RL05_date_table 
      if isempty(CSR_RL05_date_table)
        fid=file.open(p.Results.EstimDirs_file);
        d=textscan(fid,'%d %f %s %s %s %s %s %s %f %f');
        fclose(fid);
        years=d{2};
        months=cellfun(@(i) time.month2int(i),d{3});
        start=time.ToDateTime(d{ 9},'modifiedjuliandate');
        stop= time.ToDateTime(d{10},'modifiedjuliandate');
        mid=time.ToDateTime((d{ 9}+d{10})/2,'modifiedjuliandate');
        CSR_RL05_date_table=table(years,months,start,stop,mid);
      end
      rows=CSR_RL05_date_table.years==year & CSR_RL05_date_table.months==month;
      t=CSR_RL05_date_table{rows,{'mid'}};
    end
    function [m,e]=CSR_RL05_SH(varargin)
      p=inputParser; p.KeepUnmatched=true;
      p.addParameter('datadir',fullfile(getenv('HOME'),'data','csr','RL05'),@(i) ischar(i) && exist(i,'dir')~=0)
      p.parse(varargin{:})
      [m,e]=gravity.load_dir(p.Results.datadir,'csr',@gravity.parse_epoch_csr,'wilcarded_filename','*.GEO.*',varargin{:});
    end
    function [m,e]=CSR_RL05_Mascons(varargin)
      p=inputParser; p.KeepUnmatched=true;
      p.addParameter('datadir',fullfile(getenv('HOME'),'data','csr','mascons'),@(i) ischar(i) && exist(i,'dir')~=0)
      p.parse(varargin{:})
      [m,e]=gravity.load_dir(p.Results.datadir,'csr',@gravity.parse_epoch_csr,'wilcarded_filename','*.GEO',varargin{:});
    end
    %% tests
    %general test for the current object
    function out=test_parameters(field,l,w)
      switch field
      case 'something'
        %To be implemented
      otherwise
        out=simpledata.test_parameters(field,l,w);
      end
    end
    function test(method,l,t)
      if ~exist('method','var') || isempty(method)
        method='all';
      end
      if ~exist('l','var') || isempty(l)
        l=4;
      end
      if ~exist('t','var') || isempty(t)
        t=[datetime('now'),datetime('now')+seconds(1)];
      end
      nr_coeff=(l+1)^2;
      disp(['--- ',method,': l=',num2str(l)])
      switch lower(method)
      case 'all'
         for i={'reps','unit','unit rms','r','gm','minus','resample','ggm05g','c'}
           gravity.test(i{1},l);
         end
      case 'reps'
        dt={'y','mat','cs','tri','mod'};
        y=randn(1,nr_coeff);
        dd={...
          y,...
          gravity.y2mat(y),...
          gravity.mat2cs(gravity.y2mat(y)),...
          gravity.cs2tri(gravity.mat2cs(gravity.y2mat(y))),...
          gravity.cs2mod(gravity.mat2cs(gravity.y2mat(y)))...
        };
        for i=1:numel(dt)
          for j=1:numel(dt)
            out=gravity.dtc(dt{i},dt{j},dd{i});
            switch dt{j}
            case 'cs'
              c=any(any([out.C,out.S] ~= [dd{j}.C,dd{j}.S]));
            otherwise
              c=any(any(out~=dd{j}));
            end
            if c
              error([mfilename,': failed data type conversion between ''',dt{i},''' and ''',dt{j},'''.'])
            end
          end
        end
      case 'unit'
        a=gravity.unit_amplitude(l,'t',t);
        disp('- C')
        disp(a.cs(numel(t)).C)
        disp('- S')
        disp(a.cs(numel(t)).S)
        disp('- tri')
        disp(a.tri{numel(t)})
        disp('- mod')
        disp(a.mod{numel(t)})
        disp('- das')
        disp(a.das)
      case 'unit rms'
        a=gravity.unit_rms(l,'t',t);
        disp('- tri')
        disp(a.tri{numel(t)})
        disp('- drms')
        disp(a.at(t(numel(t))).drms)
      case 'r'
        a=gravity.unit_amplitude(l,'t',t);
        disp('- tri: start')
        disp(a.tri{numel(t)})
        disp('- tri: 2*R')
        disp(a.scale(a.R*2,'R').tri{numel(t)})
      case 'gm'
        a=gravity.unit_amplitude(l,'t',t);
        disp('- tri: start')
        disp(a.tri{numel(t)})
        disp('- tri: 2*GM')
        disp(a.scale(a.GM*2,'GM').tri{numel(t)})
      case 'minus'
        a=gravity.unit_amplitude(l,'t',t);
        disp('- tri: a=')
        disp(a.tri{numel(t)})
        disp('- tri: a-a.scale(2)=')
        b=a-a.scale(2);
        disp(b.tri{numel(t)})
      case 'grid'
        figure
        gravity.unit_randn(100*l,'t',t).grid.imagesc
      case 'ggm05g'
        m=gravity.load('ggm05g.gfc.txt');
        m.print
        m.grid.print
      case 'stats'
        m=gravity.load('ggm05g.gfc.txt');
        for i={'dmean','cumdmean','drms','cumdrms','dstd','cumdstd','das','cumdas'}
          figure
          m.plot(i{1},'functional','geoid','itle',[m.descriptor,' - ',i{1}]);
        end
      case 'c'
        a=gravity.unit_randn(l,'t',t);
        disp('- tri: a=')
        disp(a.tri{numel(t)})
        d=round(rand*l);
        o=round(rand*2*d)-d;
        disp(['- a.C(',num2str(d),',',num2str(o),',',datestr(t(numel(t))),')=',num2str(a.C(d,o,t(numel(t))))])
        disp(['- a.C(',num2str(d),',',num2str(o),',',datestr(t(1)),')=',num2str(a.C(d,o,t(1)))])
        v=9;
        a=a.setC(d,o,v,t(numel(t)));
        disp(['- tri: a.setC(',num2str(d),',',num2str(o),')=',num2str(v)])
        disp(a.tri{numel(t)})
        disp(['- a.C(',num2str(d),',',num2str(o),',',datestr(t(numel(t))),')=',num2str(a.C(d,o,t(numel(t))))])
        disp(['- a.C(',num2str(d),',',num2str(o),',',datestr(t(1)),')=',num2str(a.C(d,o,t(1)))])
      case 'smoothing'
        a=gravity.unit(l);
        if isdatetime(t)
          t=round(l/2);
        end
        methods={'gauss','spline','trunc'};
        for i=1:numel(methods)
          a.scale_plot(t,methods{i});
        end
        legend(methods);
      end
    end
  end
  methods
    %% constructor
    function obj=gravity(t,y,varargin)
      % input parsing
      p=inputParser;
      p.KeepUnmatched=true;
      p.addRequired( 't' ); %this can be char, double or datetime
      p.addRequired( 'y', @(i) simpledata.valid_y(i));
      %create argument object, declare and parse parameters, save them to obj
      [v,p]=varargs.wrap('parser',p,'sources',{gravity.parameters([],'obj')},'mandatory',{t,y},varargin{:});
      % get some parameters
      lmax=gravity.y_lmax(y(1,:));
      [labels,units]=gravity.labels(lmax,gravity.functional_units(p.Results.functional));
      % call superclass
      obj=obj@simpletimeseries(t,y,varargin{:},...
        'labels',labels,...
        'units',units...
      );
      % save the arguments v into this object
      obj=v.save(obj);
    end
    function obj=assign(obj,y,varargin)
      %pass it upstream
      obj=assign@simpletimeseries(obj,y,varargin{:});
      %update labels and units
      obj=obj.setlabels;
    end
    function obj=copy_metadata(obj,obj_in,more_parameters)
      if ~exist('more_parameters','var')
        more_parameters={};
      end
      %call superclass
      obj=copy_metadata@simpletimeseries(obj,obj_in,[gravity.parameters;more_parameters(:)]);
    end
    function out=metadata(obj,more_parameters)
      if ~exist('more_parameters','var')
        more_parameters={};
      end
      %call superclass
      out=metadata@simpletimeseries(obj,[gravity.parameters;more_parameters(:)]);
    end
    function out=simpletimeseries(obj)
      % call superclass
      out=simpletimeseries(obj.t,obj.y,...
        'labels',obj.labels,...
        'units',obj.functional_unit,...
        'timesystem',obj.timesystem...
      );
    end
    %% labels and units
    function obj=setlabels(obj)
      if numel(obj.labels)~=obj.width
        [obj.labels,obj.y_units]=gravity.labels(obj.lmax,obj.functional_unit);
      end
    end
    %% functional
    function out=get.funct(obj)
      if isempty(obj.functional)
        obj.functional=varargs(gravity.parameter_list).functional;
      end
      out=obj.functional;
    end
    function obj=set.funct(obj,in)
      assert(gravity.isfunctional(in),['Ilegal functional ''',in,'''.'])
      obj.functional=in;
    end
    function out=functional_name(obj)
      out=gravity.functional_names(obj.funct);
    end
    function out=functional_unit(obj)
      out=gravity.functional_units(obj.funct);
    end
    %% lmax
    function obj=set.lmax(obj,l)
      %trivial call
      if obj.lmax==l
        return
      end
      %make room for new matrix representation
      mat_new=cell(obj.length,1);
      %get existing mat representation
      mat_old=obj.mat;
      %branch between extending and truncating
      if obj.lmax<l
        for i=1:obj.length
          %make room for this epoch
          mat_new{i}=zeros(l,l);
          %propagate existing coefficients
          mat_new{i}(1:obj.lmax+1,1:obj.lmax+1)=mat_old{i};
        end
      else
        for i=1:obj.length
          %truncate
          mat_new{i}=mat_old{i}(1:l+1,1:l+1);
        end
      end
      %assign result
      obj.mat=mat_new;
    end
    function obj=set_lmax(obj,l)
      obj.lmax=l;
    end
    function out=get.lmax(obj)
      out=sqrt(obj.width)-1;
    end
    %% representations
    %returns a cell array with matrix representation
    function out=get.mat(obj)
      out=cell(obj.length,1);
      for i=1:obj.length
        out{i}=gravity.dtc('y','mat',obj.y(i,:));
      end
    end
    function obj=set.mat(obj,in)
      %sanity
      if ~iscell(in)
        error([mfilename,': input <in> must be a cell array of matrices.'])
      end
      if (numel(in)~=obj.length)
        error([mfilename,': cannot handle input <in> if it does not have the same number of elements as obj.length.'])
      end
      %make room for data
      y_now=zeros(obj.length,gravity.dtlength('y',gravity.dtlmax('mat',in{1})));
      %build data
      for i=1:obj.length
        y_now(i,:)=gravity.mat2y(in{i});
      end
      %assign data
      obj=obj.assign(y_now,'reset_width',obj.width~=size(y_now,2));
    end
    %returns a structure array with C and S representation
    function out=get.cs(obj)
      out(obj.length)=struct('C',[],'S',[]);
      for i=1:obj.length
        out(i)=gravity.dtc('y','cs',obj.y(i,:));
      end
    end
    function obj=set.cs(obj,in)
      %sanity
      if ~isstruct(in)
        error([mfilename,': input <in> must be a structure array.'])
      end
      if (numel(in)~=obj.length)
        error([mfilename,': cannot handle input <in> if it does not have the same number of elements as obj.length.'])
      end
      %make room for data
      y_now=zeros(obj.length,gravity.dtlength('y',gravity.dtlmax('cs',in)));
      %build data
      for i=1:obj.length
        y_now(i,:)=gravity.mat2y(gravity.cs2mat(in(i)));
      end
      %assign data
      obj=obj.assign(y_now);
    end
    %return a cell array with triangular matrix representation
    function out=get.tri(obj)
      out=cell(obj.length,1);
      for i=1:obj.length
        out{i}=gravity.dtc('y','tri',obj.y(i,:));
      end
    end
    function obj=set.tri(obj,in)
      %sanity
      if ~iscell(in) && ~ismatrix(in{1})
        error([mfilename,': input <in> must be a cell array of matrices.'])
      end
      if (numel(in)~=obj.length)
        error([mfilename,': cannot handle input <in> if it does not have the same number of elements as obj.length.'])
      end
      %make room for data
      y_now=zeros(obj.length,gravity.dtlength('y',gravity.dtlmax('tri',in{1})));
      %build data
      for i=1:obj.length
        y_now(i,:)=gravity.mat2y(gravity.cs2mat(gravity.tri2cs(in{i})));
      end
      %assign data
      obj=obj.assign(y_now);
    end
    %return a cell array with the mod representation
    function out=get.mod(obj)
      out=cell(obj.length,1);
      for i=1:obj.length
        out{i}=gravity.dtc('y','mod',obj.y(i,:));
      end
    end
    function obj=set.mod(obj,in)
      %sanity
      if ~iscell(in) && ~ismatrix(in{1})
        error([mfilename,': input <in> must be a cell array of matrices.'])
      end
      if (numel(in)~=obj.length)
        error([mfilename,': cannot handle input <in> if it does not have the same number of elements as obj.length.'])
      end
      %make room for data
      y_now=zeros(obj.length,gravity.dtlength('y',gravity.dtlmax('mod',in{1})));
      %build data
      for i=1:obj.length
        y_now(i,:)=gravity.mat2y(gravity.cs2mat(gravity.mod2cs(in{i})));
      end
      %assign data
      obj=obj.assign(y_now);
    end
    %% checksum of the models
    function out=get.checksum(obj)
      out=obj.norm-sqrt(obj.C(0,0).^2);
    end
    %% print
    function print(obj,tab,lprint)
      if ~exist('lprint','var') || isempty(lprint)
        lprint=3;
      end
      if ~exist('tab','var') || isempty(tab)
        tab=12;
      end
      tri_now=obj.tri;
      n=min(obj.lmax,lprint)+1;
      disp(['Coefficients up to degree ',num2str(n-1),' of the first model, at ',datestr(obj.t(1))])
      format shortg
      disp(tri_now{1}(1:n,obj.lmax-n+2:obj.lmax+n))
      format short
      %parameters
      relevant_parameters={'GM','R','functional','origin','checksum'};
      for i=1:numel(relevant_parameters)
        obj.disp_field(relevant_parameters{i},tab);
      end
      %print superclass
      print@simpletimeseries(obj,tab)
    end
    %% coefficient access
    function out=C(obj,d,o,time)
      if ~exist('time','var') || isempty(time)
        time=obj.t;
      end
      if any(size(d)~=size(o))
        error([mfilename,': inputs ''d'' and ''o'' must have the same size(s).'])
      end
      %get indexes of the cosine-coefficients
      C_idx=o>=0;
      %make room for output
      out=cell(size(time));
      for i=1:numel(out)
        out{i}=zeros(size(d));
        %retrive cosine coefficients
        out{i}( C_idx)=obj.mat{obj.idx(time(i))}( d( C_idx)+1,o( C_idx)+1);
        %retrieve sine coefficients
        out{i}(~C_idx)=obj.mat{obj.idx(time(i))}(-o(~C_idx)  ,d(~C_idx)+1);
      end
      %handle scalar quantities gracefully
      if isscalar(d)
        out_tmp=out;
        out=zeros(size(time));
        out(:)=[out_tmp{:}];
      end
    end
    function ts=ts_C(obj,d,o)
      idx=gravity.colidx(d,o,obj.lmax);
      if isempty(idx)
        ts=[];
        return
      end
      [labels,units]=gravity.labels(obj.lmax,obj.functional_unit);
      ts=simpletimeseries(...
        obj.t,...
        obj.y(:,idx),...
        'format','datetime',...
        'labels',labels(idx),...
        'timesystem',obj.timesystem,...
        'units',units(idx),...
        'descriptor',obj.descriptor...
      );    
    end
    function obj=setC(obj,d,o,values,time)
      if ~exist('time','var') || isempty(time)
        time=obj.t;
      end
      if any(size(d)~=size(o)) || any(size(d)~=size(values))
        error([mfilename,': inputs ''d'', ''o'' and ''values'' must have the same size'])
      end
      %retrieve matrix form
      mat_now=obj.mat;
      %get indexes of the cosine-coefficients
      for ti=1:numel(time)
        for i=1:numel(d)
          if o(i)>=0
            %set cosine coefficients
            mat_now{obj.idx(time(ti))}( d( i)+1,o( i)+1)=values( i);
          else
            %retrieve sine coefficients
            mat_now{obj.idx(time(ti))}(-o( i)  ,d( i)+1)=values( i);
          end
        end
      end
      %save new values
      obj.mat=mat_now;
    end
    function obj=setdegree(obj,d,values,time)
      if ~exist('time','var') || isempty(time)
        time=obj.t;
      end
      if any(size(d)~=size(values))
        error([mfilename,': inputs ''d'' and ''values'' must have the same size'])
      end
      %retrieve triangular form
      tri_now=obj.tri;
      %get indexes of the cosine-coefficients
      for ti=1:numel(time)
        for i=1:numel(d)
          %set cosine coefficients
          tri_now{obj.idx(time(ti))}(d(i)+1,:)=values( i);
        end
      end
      %save new values
      obj.tri=tri_now;
    end
    %% scaling functions
    % GM scaling
    function s=scale_GM(obj,gm)
      s=gm/obj.GM;
    end
    % radius scaling
    function s=scale_R(obj,r)
      if obj.R==r
        s=1; %quicker downstream
      else
        s=(obj.R/r).^((0:obj.lmax)+1);
      end
    end
    % functional scaling
    function s=scale_functional(obj,functional_new)
      %   Supported functionals are the following,
      %       'non-dim'   - non-dimensional Stoked coefficients.
      %       'eqwh'      - equivalent water height [m]
      %       'geoid'     - geoid height [m]
      %       'potential' - [m2/s2]
      %       'gravity'   - [m /s2], if input represents the disturbing potential,
      %                     then the output represents the gravity disturbances.
      %                     Otherwise, it represents the gravity accelerations
      %                     (-dU/dr).
      %       'anomalies' - If input represents the disturbing potential, then
      %                     the output represents the gravity anomalies.
      %                     Otherwise, it represents (-dU/dr - 2/r*U).
      %       'vert-grav-grad' - vertical gravity gradient.
      %get nr of degrees
      N=obj.lmax+1;
      %get pre-scaling
      switch lower(obj.funct)
        case 'nondim'
          %no scaling
          pre_scale=ones(N);
        otherwise
          %need to bring these coefficients down to 'non-dim' scale
          pre_scale = mod_convert_aux('nondim',from,N,obj.GM,obj.R);
      end
      %get pos-scaling
      switch lower(functional_new)
        case 'nondim'
          %no scaling
          pos_scale=ones(N);
        case 'eqwh' %[m]
          love=gravity.parameters('love','value');
          pos_scale=zeros(N);
          rho_earth=gravity.parameters('rho_earth','value');
          rho_water=gravity.parameters('rho_water','value');
          %converting Stokes coefficients from non-dimensional to equivalent water layer thickness
          for i=1:N
            deg=i-1;
            lv=interp1(...
              love(:,1),...
              love(:,2),...
              deg,'linear','extrap');
            pos_scale(i,:)=obj.R*rho_earth/rho_water/3*(2*deg+1)/(1+lv);
          end
        case 'geoid' %[m]
          pos_scale=ones(N)*obj.R;
        case 'potential' %[m2/s2]
          pos_scale=ones(N)*obj.GM/obj.R;
        case 'gravity' %[m/s2]
          %If input represents the disturbing potential, then the output
          %represents the gravity disturbances. Otherwise, it represents the
          %gravity accelerations (-dU/dr).
          deg=(0:N-1)'*ones(1,N);
          pos_scale=-obj.GM/obj.R^2*(deg+1);
        case 'anomalies'
          %If input represents the disturbing potential, then the output
          %represents the gravity anomalies. Otherwise, it represents:
          %-dU/dr - 2/r*U
          deg=(0:N-1)'*ones(1,N);
          pos_scale=obj.GM/obj.R^2*max(deg-1,ones(size(deg)));
        case 'vertgravgrad'
          deg=(0:N-1)'*ones(1,N);
          pos_scale=obj.GM/obj.R^3*(deg+1).*(deg+2);
        otherwise
          error([mfilename,': unknown scale ',functional_new])
      end
      %outputs
      s=pos_scale./pre_scale;
    end
    % Gaussan smoothing scaling
    function s=scale_gauss(obj,fwhm_degree)
      % translate smoothing radius to degree (criteria inside) 
      fwhm_degree=gravity.gauss_smoothing_degree_translate(fwhm_degree);
      %https://en.wikipedia.org/wiki/Gaussian_function#Properties
      s=exp(-4*log(2)*((0:obj.lmax)/fwhm_degree/2).^2);
%       find(abs(s-0.5)==min(abs(s-0.5)))
%       %NOTICE: the tail of this function is unstable
%       %http://dx.doi.org/10.1029/98JB02844
%       b=log(2)/(1-cos(radius/obj.R));
%       c=exp(-2*b);
%       s=zeros(1,obj.lmax+1);
%       s(1)=1;                         %degree 0
%       s(2)=s(1)*((1+c)/(1-c) - 1/b);	%degree 1
%       for l=2:obj.lmax
%         s(l+1)=-(2*l+1)/b*s(l)+s(l-1);
%       end
    end
    function s=scale_spline(obj,fwhm_degree,width_degree)
      if ~exist('width_degree','var') || isempty(width_degree)
        width_degree=5;
      end
      if fwhm_degree<=width_degree
        width_degree=fwhm_degree-1;
      end
      s=nan(1,obj.lmax+1);
      w0=max([1,fwhm_degree-width_degree]);
      w1=min([obj.lmax,fwhm_degree+width_degree]);
      if w0>=1
        s(1:w0)=1;
      end
      if width_degree<=0
        s_transition=0.5;  
      else
        s_transition=spline([1 (2*width_degree+1)],[0 1 0 0],1:(2*width_degree+1));
      end
      s(w0+1:w1+1)=s_transition(1:w1-w0+1);
      if w1+2<=obj.lmax+1
        s(w1+2:obj.lmax+1)=0;
      end
    	%sanity
      assert(~any(isnan(s)),...
        [mfilename,': found NaNs in the output. Debug needed!'])
    end
    function s=scale_trunc(obj,fwhm_degree)
      %https://en.wikipedia.org/wiki/Gaussian_function#Properties
      s=[ones(1,min([fwhm_degree+1,obj.lmax+1])),zeros(1,obj.lmax-fwhm_degree)];
%       find(abs(s-0.5)==min(abs(s-0.5)))
%       %NOTICE: the tail of this function is unstable
%       %http://dx.doi.org/10.1029/98JB02844
%       b=log(2)/(1-cos(radius/obj.R));
%       c=exp(-2*b);
%       s=zeros(1,obj.lmax+1);
%       s(1)=1;                         %degree 0
%       s(2)=s(1)*((1+c)/(1-c) - 1/b);	%degree 1
%       for l=2:obj.lmax
%         s(l+1)=-(2*l+1)/b*s(l)+s(l-1);
%       end
    end
    % scale according to number of orders in each degree
    function s=scale_nopd(obj,~)
      s=1./obj.nopd;
    end
    % scale operation agregator
    function out=scale_factor(obj,s,method)
      out=obj.(['scale_',method])(s);
    end
    function obj=scale(obj,s,method)
      if ~exist('method','var') || isempty(method)
        %handle object-to-object operations
        if isa(s,'gravity')
          %scale to object 's' values of R and GM
          obj=obj.setR(s.R);
          obj=obj.setGM(s.GM);
          %done!
          return
        end
        %trivial call
        if all(s==1)
          return
        end
        switch numel(s)
        case obj.lmax+1
          %get unit model, scaled per degree and get y-representation
          s=gravity.unit(obj.lmax,'scale_per_degree',s).y;
        case 1
          %global scaling: already handled downstream
        case obj.width
          %per-coefficients scaling: expand over all time domain
          s=ones(obj.length,1)*transpose(s(:));
        otherwise
          error([mfilename,': cannot handle scaling factors with number of elements equal to ',...
            num2str(numel(s)),'; either 1, max degree+1 (',num2str(obj.lmax+1),') or nr of coeffs (',...
            num2str(obj.width),').'])
        end
        %call mother routine
        obj=scale@simpledata(obj,s);
      else
        % input 's' assumes different meanings, dependending on the method; invoke as:
        % obj.scale('geoid','functional')
        obj=obj.scale(obj.scale_factor(s,method));
        %need to update metadata in some cases
        switch lower(method)
          case 'gm'
            obj.GM=s;
          case 'r'
            obj.R=s;
          case 'functional'
            obj.funct=s;
            obj.y_units(:)={gravity.functional_units(s)};
        end
      end
    end
    % scale plotting
    function out=scale_plot(obj,s,method)
      out.axishandle=plot(0:obj.lmax,obj.scale_factor(s,method),'LineWidth',2);
      hold on
      grid on
      xlabel('SH degree')
      ylabel('scale factor [ ]')
      out.legend_str=method;
    end
    %% GM and R operations
    function out=getGM(obj)
      out=obj.GM;
    end
    function obj=setGM(obj,gm)
      obj=obj.scale(gm,'GM');
    end
    function out=getR(obj)
      out=obj.R;
    end
    function obj=setR(obj,r)
      obj=obj.scale(r,'R');
    end
    %% derived quantities
    % number of orders in each degree
    function out=nopd(obj)
      out=2*(1:obj.lmax+1)-1;
    end
    %degree mean
    function out=dmean(obj)
      out=zeros(obj.length,obj.lmax+1);
      tri_now=obj.tri;
      n=obj.nopd';
      for i=1:obj.length
        %compute mean over each degree (don't use 'mean' here, there's lots of zeros in tri_now for the low degrees)
        out(i,:) = sum(tri_now{i},2)./n;
      end
    end
    %cumulative degree mean
    function out=cumdmean(obj)
      out=cumsum(obj.dmean,2);
    end
    %degree RMS
    function out=drms(obj)
      das=obj.das;
      out=zeros(size(das));
      l=obj.nopd;
      for i=1:obj.length
        out(i,:)=das(i,:)./sqrt(l);
      end
    end
    %cumulative degree RMS
    function ts=cumdrms(obj)
      d=sqrt(cumsum(obj.drms.^2,2));
      ts=simpletimeseries(...
        obj.t,...
        d(:,end),...
        'format','datetime',...
        'labels',{obj.functional_name},...
        'timesystem',obj.timesystem,...
        'units',obj.functional_unit,...
        'descriptor',['degree ',num2str(obj.lmax),' cumdrms of ',obj.descriptor]...
      );      
    end
    %degree STD
    function out=dstd(obj)
      out=sqrt(obj.drms.^2-obj.dmean.^2);
    end
    %cumulative degree mSTD
    function out=cumdstd(obj)
      out=sqrt(cumsum(obj.dstd.^2,2));
    end
    % returns degree amplitude spectrum for each row of obj.y. The output
    % matrix has in each row the epochs of obj.y (corresponding to the epochs
    % of the models) and for each column i the degree i-1 (this is implicit).
    function out=das(obj)
      out=zeros(obj.length,obj.lmax+1);
      tri_now=obj.tri;
      for i=1:obj.length
        %compute DAS
        out(i,:) = sqrt(sum(tri_now{i}.^2,2));
      end
    end
    % cumulative degree amplitude spectrum
    function ts=cumdas(obj)
      d=sqrt(cumsum(obj.das.^2,2));
      ts=simpletimeseries(...
        obj.t,...
        d(:,end),...
        'format','datetime',...
        'labels',{obj.functional_name},...
        'timesystem',obj.timesystem,...
        'units',obj.functional_unit,...
        'descriptor',['degree ',num2str(obj.lmax),' cumdas of ',obj.descriptor]...
      );    
    end
    % created a timeseries object with the derived quantities above
    function out=derived(obj,quantity)
      out=simpletimeseries(...
        obj.t,...
        obj.(quantity),...
        'labels',cellfun(@(i) ['deg. ',i],strsplit(num2str(0:obj.lmax)),'UniformOutput',false),...
        'units',repmat({obj.functional_unit},1,obj.lmax+1),...
        'descriptor',[quantity,' of ',obj.descriptor]...
      );
    end
    %% convert to grid
    function out=grid(obj,varargin)
      p=inputParser;
      p.KeepUnmatched=true;
      p.addParameter( 'Nlat', obj.lmax   , @(i) isnumeric(i) && isscalar(i));
      p.addParameter( 'Nlon', obj.lmax*2 , @(i) isnumeric(i) && isscalar(i));
      p.addParameter( 'Nfactor',       1 , @(i) isnumeric(i) && isscalar(i));
      % parse it
      p.parse(varargin{:});
      %easier names for the resolution
      Nlat=p.Results.Nlat*p.Results.Nfactor;
      Nlon=p.Results.Nlon*p.Results.Nfactor;
      %retrieve CS-representation
      cs_now=obj.cs;
      %initiate grid 3d-matrix
      map=nan(Nlat,Nlon,obj.length);
      %get default latitude domain
      lat=simplegrid.lat_default(Nlat);
      %make synthesis on each set of coefficients
      for i=1:obj.length
        [lon,~,map(:,:,i)]=mod_sh_synth(cs_now(i).C,cs_now(i).S,deg2rad(lat),Nlon);
      end
      %create grid structure in the form of a list
      sl=simplegrid.dti(obj.t,map,transpose(rad2deg(lon(:))),lat(:),'list');
      %initialize grid object
      out=simplegrid(sl.t,sl.map,'lon',sl.lon,'lat',sl.lat);
    end
    %% multiple operands
    function compatible(obj1,obj2,varargin)
      %call mother routine
      compatible@simpletimeseries(obj1,obj2,varargin{:});
      %shorter names
      par=gravity.compatible_parameter_list;
      for i=1:numel(par)
        % if a parameter is empty, no need to check it
        if ( iscell(obj1.(par{i})) && isempty([obj1.(par{i}){:}]) ) || ...
           ( ischar(obj1.(par{i})) && isempty( obj1.(par{i})    ) ) || ...
           ( iscell(obj2.(par{i})) && isempty([obj2.(par{i}){:}]) ) || ...
           ( ischar(obj2.(par{i})) && isempty( obj2.(par{i})    ) )
          continue
        end
        if ~isequal(obj1.(par{i}),obj2.(par{i}))
          error([mfilename,': discrepancy in parameter ',par{i},'.'])
        end
      end
    end
    function [obj1,obj2,idx1,idx2]=merge(obj1,obj2,varargin)
      %match the minimum degree (truncate)
      if obj1.lmax<obj2.lmax
        obj2.lmax=obj1.lmax;
      else
        obj1.lmax=obj2.lmax;
      end
      %match the compatible parameters
      parameters=gravity.compatible_parameter_list;
      for i=1:numel(parameters)
        p=(parameters{i});
        if ~isequal(obj1.(p),obj2.(p))
          obj2=obj2.scale(obj1.(p),p);
        end
      end
      %extend the time-domain of both objects to be in agreement with the each other.
      [obj1,obj2,idx1,idx2]=merge@simpletimeseries(obj1,obj2);
    end
    %% plot functions
    function out=plot(obj,varargin)
      % Parse inputs
      p=inputParser;
      p.KeepUnmatched=true;
      % optional arguments
      p.addParameter('method',   'drms',   @(i)ischar(i));
      p.addParameter('showlegend',false,   @(i)islogical(i));
      p.addParameter('line',     '-',      @(i)ischar(i));
      p.addParameter('title',    '',       @(i)ischar(i));
      p.addParameter('functional',obj.funct,@(i) ischar(i));
      p.addParameter('time',      [],      @(i) simpletimeseries.valid_t(i) || isempty(i));
      % parse it
      p.parse(varargin{:});
      % enforce requested functional
      if ~strcmpi(obj.funct,p.Results.functional)
        obj=obj.scale(p.Results.functional,'functional');
      end
      %consider only requested
      if ~isempty(p.Results.time)
        obj=obj.at(p.Results.time);
      end
      %build anotate
      if isempty(p.Results.title)
        out.title=obj.descriptor;
      else
        out.title=p.Results.title;
      end
      % branch on method
      switch lower(p.Results.method)
      case 'timeseries'
        %call superclass
        out.line=plot@simpletimeseries(obj,varargin{:});
      case {'cumdmean-timeseries','cumdrms-timeseries','cumdstd-timeseries','cumdas-timeseries'}
        %compute cumdrms for all epochs
        out=obj.(strrep(p.Results.method,'-timeseries','')).plot(varargin{:});
      case {'triang','trianglog10'}
        %get triangular plots (don't plot invalid entries)
        obj_masked=obj.masked;
        if isempty(obj_masked); out=[];return; end
        tri_now=obj_masked.tri;
        for i=1:numel(tri_now)
          bad_idx=(tri_now{i}==0);
          tri_now{i}(bad_idx)=NaN;
          if i>1;figure;end
          if strcmpi(p.Results.method,'trianglog10')
            out.image=imagesc([-obj.lmax,obj.lmax],[0,obj.lmax],log10(abs(tri_now{i})));
          else
            out.image=imagesc([-obj.lmax,obj.lmax],[0,obj.lmax],tri_now{i});
          end
          ylabel('SH degree')
          xlabel('SH order')
          out.cb=colorbar;
          cb.nan;
          if strcmpi(p.Results.method,'trianglog10')
            cb.label(['log_{10}(',obj.functional_name,') [',obj.functional_unit,']']);
          else
            cb.label([obj.functional_name,' [',obj.functional_unit,']']);
          end
          out.title=[out.title,' - ',datestr(obj.t(i)),', \mu=',num2str(mean(tri_now{i}(~bad_idx)))];
          title(out.title)
        end
      case {'dmean','cumdmean','drms','cumdrms','dstd','cumdstd','das','cumdas'}
        v=transpose(obj.(p.Results.method));
        switch lower(p.Results.method)
        case {'dmean','cumdmean'}
          out.line=semilogy(0:obj.lmax,abs(v),p.Results.line);hold on
        otherwise
          out.line=semilogy(0:obj.lmax,v,p.Results.line);hold on
        end
        grid on
        xlabel('SH degree')
        ylabel([obj.functional_name,'[ ',obj.functional_unit,']'])
        if p.Results.showlegend
          out.legend=legend(datestr(obj.t));
        end
        %title: append functional if no title specified
        if isempty(p.Results.title)
          switch lower(p.Results.method)
            case 'dmean',    title_str='degree mean';
            case 'cumdmean', title_str='cumul. degree mean';
            case 'drms',     title_str='degree RMS';
            case 'cumdrms',  title_str='cumul. degree RMS';
            case 'dstd',     title_str='degree STD';
            case 'cumdstd',  title_str='cumul. degree STD';
            case 'das',      title_str='degree amplit.';
            case 'cumdas',   title_str='cumul. degree amplit.';
          end
        end
        out.title=[out.title,' - ',title_str];
        title(str.clean(out.title,'title'))
      otherwise
        error([mfilename,': unknonw method ''',p.Results.method,'''.'])
      end
      out.axis=gca;
    end
    %% export functions
    function filelist=icgem(obj,varargin)
      % Parse inputs
      p=inputParser;
      p.KeepUnmatched=true;
      % optional arguments
      p.addParameter('prefix',   '',  @(i)ischar(i));
      p.addParameter('suffix',   '',  @(i)ischar(i));
      p.addParameter('delim',    '.', @(i)ischar(i));
      p.addParameter('path',     '.', @(i)ischar(i));
      p.addParameter('timefmt',  'yyyymmddTHHMMSS', @(i)ischar(i));
      p.addParameter('error_obj','',  @(i)isa(i,'gravity') || isempty(i));
      p.addParameter('modelname','unknown',         @(i)ischar(i));
      p.addParameter('errors',   'formal',          @(i)ischar(i));
      p.addParameter('norm',     'fully_normalized',@(i)ischar(i));
      % parse it
      p.parse(varargin{:});
      % get only valid entries
      obj_now=obj.masked;
      % init outputs
      filelist=cell(obj.length,1);
      % build filenames
      for i=1:obj_now.length
        f={p.Results.prefix,datestr(obj_now.t(i),p.Results.timefmt),p.Results.suffix,'gfc'};
        f=strjoin(cells.rm_empty(f),p.Results.delim);
        filelist{i}=fullfile(p.Results.path,f);
      end
      header={...
       ''... %place holder for model epoch
       ''... %place holder for time of exporting
       ['timesystem                  ',obj_now.timesystem],...
       ['descriptor                  ',obj_now.descriptor],...
       ['geopotential_functional     ',obj_now.functional],...
        'begin_of_head ===========================================================================',...
        'product_type                gravity_field',...
       ['modelname                   ',p.Results.modelname],...
       ['earth_gravity_constant      ',num2str(obj_now.GM,'%.15g')],...
       ['radius                      ',num2str(obj_now.R, '%.15g')],...
        'min_degree                  0',...
       ['max_degree                  ',num2str(obj_now.lmax,'%d')],...
        'tide_system                 zero_tide',...
       ['modelname                   ',p.Results.errors],...
       ['norm                        ',p.Results.norm],...
        'key   n   m             C                      S                 sigma C       sigma S',...
        'end_of_head ============================================================================='...
      };
      %get the data in a suitable representations
      sig=obj_now.mod;
      % handle empty error models
      if isempty(p.Results.error_obj)
        err=cell(size(sig));
        err(:)=gravity.unit(obj.lmax,'scale',0).mod;
      else
        err=p.Results.error_obj.mod;
      end
      % write data
      for i=1:obj_now.length
        %check if file is already available
        if ~exist(filelist{i},'file')
          %open file
          fid=file.open(filelist{i},'w');
          %update the header
          header{1}=['model_epoch                 ',datestr(obj_now.t(i),   p.Results.timefmt)];
          header{2}=['exported_at                 ',datestr(datetime('now'),p.Results.timefmt)];
          %write the header
          fprintf(fid,'%s\n',strjoin(header,'\n'));
          %paranoid sanity
          assert(all(sig{i}(:,1)==err{i}(:,1)) && all(sig{i}(:,2)==err{i}(:,2)),...
            'degree/order domain discrepancy between signal and error')
          %write the data
          for j=1:numel(sig{i}(:,1))
            fprintf(fid,'gfc %3d %3d %23.15e %23.15e %14.8g %14.8g\n',...
              [sig{i}(j,1),sig{i}(j,2),sig{i}(j,3),sig{i}(j,4),err{i}(j,3),err{i}(j,4)]...
            );
          end
          %close the file
          fclose(fid);
          disp(['Finished writing:  ',filelist{i}])
        else
          disp(['Already available: ',filelist{i}])
        end
      end
    end
  end
end

%% load interfaces
function [m,e]=load_gsm(filename,time)
  %default time
  if ~exist('time','var') || isempty(time)
    time=datetime('now');
  end
  %open file
  fid=file.open(filename);
  modelname=''; GM=0; radius=0; Lmax=0; %Mmax=0;
  % Read header
  s=fgets(fid);
  while(strncmp(s, 'GRCOF2', 6) == 0)
     if (keyword_search(s, 'FIRST'))
       modelname =strtrim(s(7:end));
     end
     if (keyword_search(s, 'EARTH'))
%        x=str2num(s(7:end));
       x=str.num(s(7:end));
       GM=x(1);
       radius=x(2);
     end
     if keyword_search(s, 'SHM') && ~keyword_search(s, 'SHM*')
%        x=str2num(s(4:16));
       x=str.num(s(4:16));
       Lmax=x(1);
       %Mmax=x(2);
       permanent_tide=strfind(s,'inclusive permanent tide');
     end
     s=fgets(fid);
  end
  %sanity
  if sum(s)<0
     error([mfilename,': Problem with reading the GRCOF2 file ''',filename,'''.'])
  end
  %make room for coefficients
  mi.C=zeros(Lmax+1);
  mi.S=zeros(Lmax+1);
  ei.C=zeros(Lmax+1);
  ei.S=zeros(Lmax+1);
  % read coefficients
  while (s>=0)
    %skip empty lines
    if numel(s)<5
      s=fgets(fid);
      continue
    end
    %get numeric data
%     x=str2num(s(7:76)); %#ok<*ST2NM>
    x=str.num(s(7:76));
    %save degree and order
    d=x(1)+1;
    o=x(2)+1;
    %check if this is a valid line
    if strcmp(s(1:6),'GRCOF2')
      mi.C(d,o)=x(3);
      mi.S(d,o)=x(4);
      if (numel(x)>=6),
         ei.C(d,o)=x(5);
         ei.S(d,o)=x(6);
      end
    else
      error([mfilename,': unexpected tag in line: ''',s,''.'])
    end
    % read next line
    s=fgets(fid);
  end
  %fix permanent_tide
  if permanent_tide
    mi.C(3,1)=mi.C(3,1)-4.173e-9;
  end
  %initializing data object
  m=gravity(...
    time,...
    gravity.dtc('cs','y',mi),...
    'GM',GM,...
    'R',radius,...
    'descriptor',modelname,...
    'origin',filename...
  );
  if any(ei.C(:)~=0) || any(ei.S(:)~=0)
    %initializing error object
    e=gravity(...
      time,...
      gravity.dtc('cs','y',ei),...
      'GM',GM,...
      'R',radius,...
      'descriptor',['error of ',modelname],...
      'origin',filename...
    );
  end
end
function [m,e]=load_csr(filename,time)
  %default time
  if ~exist('time','var') || isempty(time)
    time=datetime('now');
  end
  %open file
  fid=file.open(filename);
  modelname=''; Lmax=360; %Mmax=0;
  % Read header
  % skip first line (with a fortran format specifier)
  fgets(fid);
  %get GM and radius from the second line
  s=fgets(fid);
      GM=str.num(s(21:40));
  radius=str.num(s(41:60));
  %sanity
  if GM==0 || radius==0
    error([mfilename,': Problem with reading the CSR file ''',filename,''', could not find GM and R constants.'])
  end
  if sum(s)<0
    error([mfilename,': Problem with reading the CSR file ''',filename,'''.'])
  end
  %make room for coefficients
  mi.C=zeros(Lmax+1);
  mi.S=zeros(Lmax+1);
  ei.C=zeros(Lmax+1);
  ei.S=zeros(Lmax+1);
  Lmax=0;
  % read coefficients
  while (s>=0)
    %skip irrelevant lines
    if strncmp(s, 'RECOEF', 6) == 0 && strncmp(s, 'SUMGEO', 6) == 0
      s=fgets(fid);
      continue
    end
    %save degree and order
%     d=str2num(s( 7: 9))+1;
    d=str.num(s(7:9))+1;
    if d>Lmax;Lmax=d;end
%     o=str2num(s(10:12))+1;
    o=str.num(s(10:12))+1;
%     mi.C(d,o)=str2num(s(13:33));
    mi.C(d,o)=str.num(s(13:33));
%     mi.S(d,o)=str2num(s(34:54));
    mi.S(d,o)=str.num(s(34:54));
%     ei.C(d,o)=str2num(s(55:65));
    ei.C(d,o)=str.num(s(55:65));
%     ei.S(d,o)=str2num(s(66:76));
    ei.S(d,o)=str.num(s(66:76));
    % read next line
    s=fgets(fid);
  end
  %crop containers
  mi.C=mi.C(1:Lmax,1:Lmax);
  mi.S=mi.S(1:Lmax,1:Lmax);
  ei.C=ei.C(1:Lmax,1:Lmax);
  ei.S=ei.S(1:Lmax,1:Lmax);
%   %fix permanent_tide
%   if permanent_tide
%     mi.C(3,1)=mi.C(3,1)-4.173e-9;
%   end
  %initializing data object
  m=gravity(...
    time,...
    gravity.dtc('cs','y',mi),...
    'GM',GM,...
    'R',radius,...
    'descriptor',modelname,...
    'origin',filename...
  );
  %initializing error object
  e=gravity(...
    time,...
    gravity.dtc('cs','y',ei),...
    'GM',GM,...
    'R',radius,...
    'descriptor',['error of ',modelname],...
    'origin',filename...
  );
end
function [m,e,trnd,acos,asin]=load_icgem(filename,time)
%This function is an adaptation of icgem2mat.m from rotating_3d_globe, by
%Ales Bezdek, which can be found at:
%
%http://www.asu.cas.cz/~bezdek/vyzkum/rotating_3d_globe/
%
%The original header is transcribed below.
%
%J.Encarnacao (j.g.deteixeiradaencarnacao@tudelft.nl) 11/2013
%
% ICGEM2MAT   Reads geopotential coefficients from an ICGEM file and saves them in a mat file.
%
% Usage:
%
%       icgem2mat
%
% finds all the ICGEM files (*.gfc) in the current directory,
% reads the geopotential coefficients, transforms them into Matlab variables:
%       header...structure with Icgem header information
%       mi.C(n+1,m+1), mi.S(n+1,m+1)...harmonic coefficients C(n,m), S(n,m)
%
% The new mat file with the same name is moved into 'data_icgem' subdirectory;
% the original gfc file is moved into 'data_icgem/gfc/' subdirectory.
%
% Add the 'data_icgem' folder into your Matlab path.
% The model coefficients are then loaded by typing, e.g.:
%
%          load egm2008
%
% To display the C(2,0) zonal term type
%
%          mi.C(3,1)
%
%
% See also compute_geopot_grids
%
% Ales Bezdek, bezdek@asu.cas.cz, 11/2012
%
% clear
% NMAX=360;
% NMAX=1e100;  %it is possible to limit the maximum degree read from the gfc file
% adr_data='./';
% adr_kam='./data_icgem/';
%
% seznam_soub=dir(adr_data);
% soub={seznam_soub.name};   %cell with filenames
% for i=1:length(soub)
%    jm=soub{i};
%    if length(jm)>4 && strcmpi(jm(end-3:end),'.gfc')
%       soub1=jm(1:end-4);
%       fprintf('Gfc file processed: %s\n',soub1);
%       filename=[adr_data soub1 '.gfc'];

  %default time
  if ~exist('time','var') || isempty(time)
    time=datetime('now');
  end
  %open file
  fid=file.open(filename);
  % init header
  header=struct(...
      'product_type',           '',...
      'modelname',              '',...
      'model_content',          '',...
      'earth_gravity_constant', [],...
      'radius',                 [],...
      'max_degree',             [],...
      'errors',                 '',...
      'norm',                   '',...
      'tide_system',            '',...
      'filename',               filename...
  );
  % Read header
  s=fgets(fid);
  fn=fieldnames(header);
  while(strncmp(s, 'end_of_head', 11) == 0 && sum(s)>=0)
    for j=1:numel(fn)
      f=fn{j};
      if (keyword_search(s,f))
        valuestr=strtrim(s(length(f)+1:end));
        switch class(header.(f))
          case 'double'
            header.(f)=str2double(strrep(valuestr,'D','e'));
          case 'char'
            header.(f)=valuestr;
          otherwise
          error([mfilename,': cannot handle class ',class(header.(f)),'.'])
        end
      end
    end
    s=fgets(fid);
  end
  if s<0
    error([mfilename,'Problem reading the gfc file.'])
  end
  % sanity on max degree
  if isempty(header.max_degree)
    error([mfilename,': could not determine maximum degree of model ''',filename,'''.'])
  end
  % make room for coefficients
  mi=struct('C',zeros(header.max_degree+1),'S',zeros(header.max_degree+1),'t0',[]);
  ei=struct('C',zeros(header.max_degree+1),'S',zeros(header.max_degree+1));
  trnd=struct('C',[],'S',[]);
  acos=struct('C',[],'S',[]);
  asin=struct('C',[],'S',[]);
  %iterators
  i_t0=0;
  i_trnd=0; %pocet clenu s trendem
  i_acos=0; %pocet clenu
  i_asin=0; %pocet clenu
  i_gfc=0;
  %read data
  s=fgets(fid);
  while (s>=0)
    %skip empty lines
    if numel(s)<5
      s=fgets(fid);
      continue
    end
    %retrieve keywords, degree and order
%     x=str2num(s(5:end));
    x=str.num(s(5:end));
    n=x(1)+1;
    m=x(2)+1;
    if strcmp(s(1:4),'gfct')
      i_t0=i_t0+1;
      mi.C(n,m)=x(3);
      mi.S(n,m)=x(4);
      [yr,mn,dy]=ymd2cal(x(end)/1e4);
      yrd=jd2yr(cal2jd(yr,mn,dy));
      if isempty(mi.t0)
        mi.t0=zeros(grep_nr_occurences(filename,'gfct'));
        if numel(mi.t0)==0; error([mfilename,'Problem with gfct']); end
      end
      mi.t0(i_t0,:)=[n m yrd];
      if (strcmp(header.errors,'formal') || ...
          strcmp(header.errors,'calibrated') || ...
          strcmp(header.errors,'calibrated_and_formal'))
        ei.C(n,m)=x(5);
        ei.C(n,m)=x(6);
      end
    elseif strcmp(s(1:3),'gfc')
      mi.C(n,m)=x(3);
      mi.S(n,m)=x(4);
      if (strcmp(header.errors,'formal') || ...
          strcmp(header.errors,'calibrated') || ...
          strcmp(header.errors,'calibrated_and_formal'))
        ei.C(n,m)=x(5);
        ei.C(n,m)=x(6);
      end
      i_gfc=i_gfc+1;
    elseif strcmp(s(1:4),'trnd') || strcmp(s(1:3),'dot')
      if isempty(trnd.C)
        trnd.C=zeros(grep_nr_occurences(filename,'trnd')+grep_nr_occurences(filename,'dot'),3); trnd.S=trnd.C;
        if numel(trnd.C)==0; error([mfilename,'Problem with trnd']); end
      end
      i_trnd=i_trnd+1;
      trnd.C(i_trnd,:)=[n m x(3)];
      trnd.S(i_trnd,:)=[n m x(4)];
    elseif strcmp(s(1:4),'acos')
      if isempty(acos.C)
        acos.C=zeros(grep_nr_occurences(filename,'acos'),4); acos.S=acos.C;
        if numel(asin.C)==0; error([mfilename,'Problem with acos']); end
      end
      i_acos=i_acos+1;
      acos.C(i_acos,:)=[n m x(3) x(end)];
      acos.S(i_acos,:)=[n m x(4) x(end)];
    elseif strcmp(s(1:4),'asin')
      if isempty(asin.C)
        asin.C=zeros(grep_nr_occurences(filename,'asin'),4); asin.S=asin.C;
        if numel(asin.C)==0; error([mfilename,'Problem with asin']); end
      end
      i_asin=i_asin+1;
      asin.C(i_asin,:)=[n m x(3) x(end)];
      asin.S(i_asin,:)=[n m x(4) x(end)];
    else
      error([mfilename,'A problem occured in gfc data.']);
    end
    s=fgets(fid);
  end
  fclose(fid);
  %handle the tide system
  switch header.tide_system
    case 'zero_tide'
      %do nothing, this is the default
    case {'free_tide','tide_free'}
      mi.C(3,1)=mi.C(3,1)-4.173e-9;
      header.tide_system='zero_tide';
    case 'mean_tide'
      %http://mitgcm.org/~mlosch/geoidcookbook/node9.html
      mi.C(3,1)=mi.C(3,1)+1.39e-8;
      header.tide_system='zero_tide';
    otherwise
      %the tide system is not documented, so make some assumptions
      switch header.modelname
        case 'GROOPS'
          %do nothing, Norber Zehentner's solutions are zero tide
        otherwise
          error([mfilename,': unknown tide system ''',header.tide_system,'''.'])
      end
  end
  %initializing data object
  m=gravity(...
    time,...
    gravity.dtc('cs','y',mi),...
    'GM',header.earth_gravity_constant,...
    'R',header.radius,...
    'descriptor',header.modelname,...
    'origin',header.filename...
  );
  if any(ei.C(:)~=0) || any(ei.S(:)~=0)
    %initializing error object
    e=gravity(...
      time,...
      gravity.dtc('cs','y',ei),...
      'GM',header.earth_gravity_constant,...
      'R',header.radius,...
      'descriptor',['error of ',header.modelname],...
      'origin',header.filename...
    );
  else
    e=gravity.unit(m.lmax,...
      'scale',0,...
      't',time,...
      'GM',header.earth_gravity_constant,...
      'R',header.radius,...
      'descriptor',['error of ',header.modelname],...
      'origin',header.filename...
    );
  end
end
function [m,e]=load_mod(filename,time)
  %default time
  if ~exist('time','var') || isempty(time)
    time=datetime('now');
  end
  %loading data
  [mi,headerstr]=file.textscan(filename);
  %init constants
  header=struct(...
    'GM',gravity.default_list.GM,...
    'R',gravity.default_list.R,...
    'name','unknown'...
  );
  %going through all header lines
  for i=1:numel(headerstr)
    %checking if this is one of the ID strings
    for j=1:fieldnames(header)
      fieldname=j{1};
      if keyword_search(headerstr{i},[fieldname,':'])
        valuestr=strrep(headerstr{i},[fieldname,':'],'');
        switch class(header.(fieldname))
        case 'double'
          header.(fieldname)=str2double(valuestr);
        case 'char'
          header.(fieldname)=valuestr;
        otherwise
          error([mfilename,': cannot handle class ',class(header.(fieldname)),'.'])
        end
      end
    end
  end
  %initializing data object
  m=gravity(...
    time,...
    gravity.dtc('mod','y',mi),...
    'GM',header.GM,...
    'R',header.R,...
    'descriptor',header.name,...
    'origin',filename...
  );
  %no error info on mod format
  e=[];
end

%% Aux functions
function out=keyword_search(line,keyword)
    out=strncmp(strtrim(line),       keyword,         length(keyword)) || ...
        strncmp(strtrim(line),strrep(keyword,' ','_'),length(keyword));
end
function out=grep_nr_occurences(filename,pattern)
   [~, result] =system(['grep -c ',pattern,' ',filename]);
   out=str2double(result);
end

%% Spherical Harmonic synthesis
function [long,lat,grid_out]=mod_sh_synth(c,s,lat,NLon)
% [LONG,LAT,GRID]=MOD_SH_SYNTH(C,S) is the low-level spherical harmonic
% synthesis routine. It should be a self-contained script. Inputs C and S
% are the cosine and sine coefficients, organized in lower triangle
% matrices, with constant degree in each row and constant order in each
% column, sectorial coefficients are in the diagonals, zonal coefficients
% are in the first column of matrix C (first column of S matrix is zeros).
%
%   MOD_SH_SYNTH(C,S,LAT,NLON) with the optional inputs LAT, NLON causes
%   the synthesis to be done on the latitudes specified with vector LAT and
%   along the #NLON equidistant number of points along the longitudes
%   domain.
%
%   Output LONG is a horizontal vector [0:2*pi].
%   Output LAT is a vertical vector [-pi/2:pi/2].
%   Output GRID is a matrix with size [length(lat) NLon]
%
%   All angular quantities are in radians.

% Created by J.Encarnacao <J.deTeixeiradaEncarnacao@tudelft.nl>
% List of changes:
%
%   P.Inacio <p.m.g.inacio@tudelft.nl>, 10/2011, Added check for repeated
%       meridians at 0 and 2*pi. If they both exist and have the same Also
%       added a more robust check that grids are regular taking into
%       account a numerical error threshold.
%   P.Inacio <p.m.g.inacio@tudelft.nl>, 03/2012, The algorightm upon which
%       this function relies only uses the number of points along
%       longitude. Therefore, to avoid misinterpretations the input LONG
%       has been replaces with the number of points along the longitude
%       domain. Further interpolation to arbitrary sets of longitudes,
%       regular or irregular is implemented outside this routine, in
%       mod_synthesis.

  % Defaults
  %check dimensions
  if any(size(c) ~= size(s))
       error([mfilename,': inputs <c> and <s> must have the same size.'])
  end
  if size(c,1) ~= size(c,2)
      error([mfilename,': inputs <c> and <s> must be square matrices'])
  end

  %calculating max resolution
  L = size(c,1)-1;
  N = max([1 L]);
  % %%% OLD CODE
  % N = max([1,min([L,360])]);
  % %%%

  %building latitude domain (if not given)
  if ~exist('lat','var') || isempty(lat)
      lat=linspace(-pi/2,pi/2,N)';
  end
  %setting default number of points along latitude
  if ~exist('NLon','var') || isempty(NLon)
      NLon = 2*N;
  elseif ~isscalar(NLon) || ~isnumeric(NLon)
      error([mfilename,': input <Nlon> must be a numeric scalar.'])
  end

  %create internal longitude domain - only used for output.
  long=linspace(0,2*pi,NLon+1);
  % removing duplicate zero longitude
  long(end)=[];

  %checking (possible) inputs
  % NOTE: Requiring latitude to be vertical is a bit stupid, but it general
  %       it allows it to be distinguished from the longitude avoiding
  %       possible usage error.
  if size(lat,2) ~= 1
      error([mfilename,': input <lat> must be a vertical vector.'])
  end

  %check latitude domain
  if max(lat) > pi/2 || min(lat) < -pi/2
      error([mfilename,': input <lat> does not seem to be in radians or outside legal domain [-pi/2,pi/2].'])
  end

  %need co-latitude
  clat=pi/2-lat;

  % calculating Legendre polynomials, P{latitude}
  P=legendre_latitude(L,clat);

  %building the grids
  grid_out = zeros(length(clat),NLon);
  for i=1:length(clat)
      %calculating Fourier coefficients
      a=zeros(L+1,1);
      b=zeros(L+1,1);
      for m=0:L
          n=m:L;
          a(m+1) = sum(c(n+1,m+1).*P{i}(n+1,m+1));
          b(m+1) = sum(s(n+1,m+1).*P{i}(n+1,m+1));
      end

      %FFT
      grid_out(i,:) = real(fft(a+1i*b,NLon))';
  end
end
function out = legendre_latitude(L,lat)
  %getting legendre coefficient, per degree
  P=legendre_degree(L,lat);
  %building legendre coefficients, per latitude
  out = cell(length(lat),1);
  for i=1:length(lat)
      out{i} = zeros(L+1,L+1);
      for n=0:L
          out{i}(n+1,1:n+1) = P{n+1}(:,i)';
      end
  end
end
function out = legendre_degree(L,lat)
  if ~isvector(lat)
      error([mfilename,': input <lat> must be a vector.'])
  end
  %getting legendre coefficients, per degree
  out=cell(1,L+1);
  for n=0:L
      out{n+1}=legendre(n,cos(lat'),'norm')*2;
      out{n+1}(1,:)=out{n+1}(1,:)/sqrt(2);
  %     % P.Inacio - testing - manual normalization
  %     m = (0:n)';
  %     out{n+1}=legendre(n,cos(lat'));
  %     out{n+1}=repmat(sqrt((2*n+1)*factorial(n-m)./factorial(n+m)),[1 length(lat)]).*out{n+1};
  %     % P.Inacio - testing - no normalization
  %     out{n+1}=legendre(n,cos(lat'),'norm')*2;
  end
end

%% Auxiliarly data
function [t,s,e]=GetGraceC20(varargin)
  p=inputParser;
  p.KeepUnmatched=true;
  p.addParameter('mode','read', @(i) ischar(i))
  p.addParameter('file',fullfile(fileparts(which(mfilename)),'TN-07_C20_SLR.txt'),@(i) ischar(i))
  p.addParameter('url','ftp://podaac.jpl.nasa.gov/allData/grace/docs/TN-07_C20_SLR.txt',@(i) ischar(i))
  p.addParameter('grace_models_dir',[getenv('HOME'),'/media/data2/data/grace/L2/GFZ/RL05'],@(i) ischar(i))
  p.parse(varargin{:})
  switch lower(p.Results.mode)
  case 'read'
    %download data, if not already
    if isempty(dir(p.Results.file))
      GetGraceC20('mode','set');
    end
    [t,s,e]=GetGraceC20('mode','get');
  case 'get'
    %open the file
    fid=file.open(p.Results.file);
    %sanity
    if fid<=0
      error([mfilename,': cannot open the data file ''',p.Results.file,'''.'])
    end
    %skip header info
    found=false;
    while ~found
      found=strcmp(fgetl(fid),'PRODUCT:');
    end
    %read the data
    d=textscan(fid,'%7.1f%10.4f%22.13f%8.4f%8.4f','CommentStyle','*');
    %close the file
    fclose(fid);
    % outputs
    t=datetime(d{1},'ConvertFrom','modifiedjuliandate');
    s=d{3};
    e=d{5}*1e-10;
  case 'set'
    fid=file.open(p.Results.file,'w+');
    fprintf(fid,'%s',urlread(p.Results.url));
    fclose(fid);
  otherwise
    error([mfilename,': unknown mode ''',p.Results.mode,'''.'])
  end
end
